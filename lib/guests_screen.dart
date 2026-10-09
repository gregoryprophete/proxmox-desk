import 'dart:async';

import 'package:flutter/material.dart';

import 'config.dart';
import 'console_page.dart';
import 'proxmox_api.dart';

/// Native list of virtual machines and containers with power controls.
class GuestsScreen extends StatefulWidget {
  const GuestsScreen({super.key, required this.config});

  final ServerConfig config;

  @override
  State<GuestsScreen> createState() => _GuestsScreenState();
}

class _GuestsScreenState extends State<GuestsScreen> {
  late final ProxmoxApi _api = ProxmoxApi(widget.config);
  Timer? _timer;
  List<Guest>? _guests;
  String? _error;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.config.hasToken) {
      _refresh();
      _timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _api.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final guests = await _api.guests();
      if (!mounted) return;
      setState(() {
        _guests = guests;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      _loading = false;
    }
  }

  Future<void> _power(Guest g, String action) async {
    if (action == 'stop') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Force stop ${g.name}?'),
          content: const Text(
              'This is like pulling the power cable. Unsaved work in the guest is lost.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Stop')),
          ],
        ),
      );
      if (ok != true) return;
    }
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _api.power(g, action);
      messenger.showSnackBar(SnackBar(content: Text('Sent $action to ${g.name}')));
      await Future<void>.delayed(const Duration(seconds: 2));
      await _refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(describeError(e))));
    }
  }

  void _openConsole(Guest g) {
    final url = widget.config.webUri({
      'console': g.isContainer ? 'lxc' : 'kvm',
      g.isContainer ? 'xtermjs' : 'novnc': '1',
      'vmid': '${g.vmid}',
      'vmname': g.name,
      'node': g.node,
      'resize': 'scale',
    });
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ConsolePage(
        config: widget.config,
        title: '${g.vmid} · ${g.name}',
        url: url,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!widget.config.hasToken) {
      return const _Message(
        'Add an API token in Settings to list your virtual machines and containers here.',
      );
    }
    final guests = _guests;
    if (guests == null) {
      return _error == null
          ? const Center(child: CircularProgressIndicator())
          : _Message(_error!, onRetry: _refresh);
    }
    final running = guests.where((g) => g.running).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: Text('$running of ${guests.length} running',
                    style: theme.textTheme.titleMedium),
              ),
              IconButton(
                  tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _refresh),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ),
        Expanded(
          child: guests.isEmpty
              ? const _Message('No virtual machines or containers visible to this token.')
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  itemCount: guests.length,
                  itemBuilder: (context, i) => _GuestTile(
                    guest: guests[i],
                    onPower: (a) => _power(guests[i], a),
                    onConsole: () => _openConsole(guests[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _GuestTile extends StatelessWidget {
  const _GuestTile({required this.guest, required this.onPower, required this.onConsole});

  final Guest guest;
  final ValueChanged<String> onPower;
  final VoidCallback onConsole;

  static String _gb(int bytes) => (bytes / 1073741824).toStringAsFixed(1);

  static String _uptime(int s) {
    final d = s ~/ 86400, h = (s % 86400) ~/ 3600, m = (s % 3600) ~/ 60;
    if (d > 0) return '${d}d ${h}h';
    if (h > 0) return '${h}h ${m}m';
    return '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final g = guest;
    final kind = g.isContainer ? 'Container' : 'VM';
    final detail = g.running
        ? '$kind on ${g.node} · CPU ${(g.cpu * 100).toStringAsFixed(0)}% of ${g.maxCpu} · '
            'RAM ${_gb(g.mem)} / ${_gb(g.maxMem)} GB · up ${_uptime(g.uptime)}'
        : '$kind on ${g.node} · ${g.status}';
    return Card(
      child: ListTile(
        leading: Icon(
          g.isContainer ? Icons.inventory_2_outlined : Icons.desktop_windows_outlined,
          color: g.running ? Colors.green : Theme.of(context).disabledColor,
        ),
        title: Text('${g.vmid} · ${g.name}'),
        subtitle: Text(detail),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (g.running)
              IconButton(
                  tooltip: 'Console', icon: const Icon(Icons.terminal), onPressed: onConsole)
            else
              IconButton(
                tooltip: 'Start',
                icon: const Icon(Icons.play_arrow),
                onPressed: () => onPower('start'),
              ),
            PopupMenuButton<String>(
              tooltip: 'Power',
              onSelected: onPower,
              itemBuilder: (_) => [
                if (!g.running) const PopupMenuItem(value: 'start', child: Text('Start')),
                if (g.running) ...const [
                  PopupMenuItem(value: 'shutdown', child: Text('Shut down')),
                  PopupMenuItem(value: 'reboot', child: Text('Reboot')),
                  PopupMenuItem(value: 'stop', child: Text('Force stop')),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text, {this.onRetry});

  final String text;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: 12),
              OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ],
        ),
      ),
    );
  }
}
