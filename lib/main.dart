import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:window_manager/window_manager.dart';

import 'config.dart';
import 'guests_screen.dart';
import 'setup_screen.dart';
import 'web_pane.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isDesktop) await windowManager.ensureInitialized();
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
    webViewAvailable = await WebViewEnvironment.getAvailableVersion() != null;
  }
  final config = await ConfigStore.load();
  runApp(ProxmoxDeskApp(initial: config));
}

class ProxmoxDeskApp extends StatefulWidget {
  const ProxmoxDeskApp({super.key, this.initial});

  final ServerConfig? initial;

  @override
  State<ProxmoxDeskApp> createState() => _ProxmoxDeskAppState();
}

class _ProxmoxDeskAppState extends State<ProxmoxDeskApp> {
  late ServerConfig? _config = widget.initial;
  bool _editing = false;

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final Widget home;
    if (config == null || _editing) {
      home = SetupScreen(
        existing: config,
        onSaved: (c) => setState(() {
          _config = c;
          _editing = false;
        }),
        onCancel: config == null ? null : () => setState(() => _editing = false),
      );
    } else {
      home = HomeScreen(
        // A new key rebuilds everything when the server or token changes.
        key: ValueKey('${config.host}:${config.port}/${config.tokenId}/${config.tokenSecret.hashCode}'),
        config: config,
        onEdit: () => setState(() => _editing = true),
        onForget: () async {
          await ConfigStore.clear();
          setState(() => _config = null);
        },
      );
    }
    return MaterialApp(
      title: 'Proxmox Desk',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFE57000),
          brightness: Brightness.dark,
        ),
      ),
      home: home,
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.config,
    required this.onEdit,
    required this.onForget,
  });

  final ServerConfig config;
  final VoidCallback onEdit;
  final VoidCallback onForget;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Open on the guest list when a token exists, otherwise on the web interface.
  late int _index = widget.config.hasToken ? 0 : 1;

  static const _tabs = [
    (icon: Icons.dns_outlined, label: 'Guests'),
    (icon: Icons.public, label: 'Web interface'),
    (icon: Icons.settings_outlined, label: 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    // IndexedStack keeps the web interface signed in while you switch tabs.
    final body = IndexedStack(
      index: _index,
      children: [
        GuestsScreen(config: widget.config),
        WebPane(config: widget.config),
        _Settings(config: widget.config, onEdit: widget.onEdit, onForget: widget.onForget),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        return Scaffold(
          body: SafeArea(
            child: wide
                ? Row(
                    children: [
                      NavigationRail(
                        selectedIndex: _index,
                        labelType: NavigationRailLabelType.all,
                        onDestinationSelected: (i) => setState(() => _index = i),
                        destinations: [
                          for (final t in _tabs)
                            NavigationRailDestination(icon: Icon(t.icon), label: Text(t.label)),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: body),
                    ],
                  )
                : body,
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _index,
                  onDestinationSelected: (i) => setState(() => _index = i),
                  destinations: [
                    for (final t in _tabs)
                      NavigationDestination(icon: Icon(t.icon), label: t.label),
                  ],
                ),
        );
      },
    );
  }
}

class _Settings extends StatelessWidget {
  const _Settings({required this.config, required this.onEdit, required this.onForget});

  final ServerConfig config;
  final VoidCallback onEdit;
  final VoidCallback onForget;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Server'),
          subtitle: Text('${config.host}:${config.port}'),
        ),
        ListTile(
          leading: const Icon(Icons.key_outlined),
          title: const Text('API token'),
          subtitle: Text(config.hasToken ? config.tokenId : 'Not set'),
        ),
        ListTile(
          leading: const Icon(Icons.verified_user_outlined),
          title: const Text('Certificate'),
          subtitle: SelectableText(
            config.fingerprint.isEmpty
                ? 'Trusted by this device'
                : 'Self-signed, accepted:\n${config.fingerprint}',
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.tonal(onPressed: onEdit, child: const Text('Change server or token')),
            OutlinedButton(onPressed: onForget, child: const Text('Forget this server')),
          ],
        ),
      ],
    );
  }
}
