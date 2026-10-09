import 'package:flutter/material.dart';

import 'config.dart';
import 'proxmox_api.dart';

/// First-run screen, also used to change the server later.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, this.existing, required this.onSaved, this.onCancel});

  final ServerConfig? existing;
  final ValueChanged<ServerConfig> onSaved;
  final VoidCallback? onCancel;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final _host = TextEditingController(text: widget.existing?.host ?? '');
  late final _port = TextEditingController(text: '${widget.existing?.port ?? 8006}');
  late final _tokenId = TextEditingController(text: widget.existing?.tokenId ?? '');
  late final _secret = TextEditingController(text: widget.existing?.tokenSecret ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _tokenId.dispose();
    _secret.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    // Accept a bare address or a pasted URL such as https://10.0.0.5:8006/
    var raw = _host.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = 'Enter the server address.');
      return;
    }
    if (!raw.contains('://')) raw = 'https://$raw';
    final parsed = Uri.tryParse(raw);
    if (parsed == null || parsed.host.isEmpty) {
      setState(() => _error = 'That address does not look right.');
      return;
    }
    final host = parsed.host;
    final port = parsed.hasPort ? parsed.port : (int.tryParse(_port.text.trim()) ?? 8006);
    final tokenId = _tokenId.text.trim();
    final secret = _secret.text.trim();
    if (tokenId.isNotEmpty != secret.isNotEmpty) {
      setState(() => _error = 'Fill in both the token ID and the secret, or leave both empty.');
      return;
    }
    if (tokenId.isNotEmpty && !(tokenId.contains('@') && tokenId.contains('!'))) {
      setState(() => _error = 'The token ID looks like user@realm!name, for example root@pam!desk.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final probe = await ProxmoxApi.probe(host, port);
      var fingerprint = '';
      if (!probe.trusted) {
        final alreadyAccepted = widget.existing?.host == host &&
            widget.existing?.fingerprint == probe.fingerprint;
        if (!alreadyAccepted) {
          if (!mounted) return;
          final ok = await _confirmCertificate(probe.fingerprint);
          if (ok != true) return;
        }
        fingerprint = probe.fingerprint;
      }
      final config = ServerConfig(
        host: host,
        port: port,
        tokenId: tokenId,
        tokenSecret: secret,
        fingerprint: fingerprint,
      );
      if (config.hasToken) {
        final api = ProxmoxApi(config);
        try {
          await api.version();
        } finally {
          api.close();
        }
      }
      await ConfigStore.save(config);
      if (!mounted) return;
      widget.onSaved(config);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirmCertificate(String fingerprint) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Trust this server?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The server uses a self-signed certificate, which is normal for Proxmox. '
              'Compare this fingerprint with the one shown in Proxmox under '
              'your node > System > Certificates.',
            ),
            const SizedBox(height: 12),
            SelectableText(fingerprint, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Trust')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Connect to Proxmox', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 20),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _host,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Server address',
                          hintText: '10.147.17.20',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _port,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Port',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('API token (optional)', style: theme.textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'Adds the built-in guest list with start and stop buttons. '
                  'Without it the app still opens the web interface.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tokenId,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Token ID',
                    hintText: 'root@pam!desk',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _secret,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(
                    labelText: 'Secret',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _busy ? null : _connect(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _connect,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_busy ? 'Connecting…' : 'Connect'),
                  ),
                ),
                if (widget.onCancel != null)
                  TextButton(onPressed: _busy ? null : widget.onCancel, child: const Text('Cancel')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
