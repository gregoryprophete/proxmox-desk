import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'config.dart';
import 'web_pane.dart';

/// A guest's console in its own page, with a remote-desktop style full screen
/// mode: the window covers the whole display and only a small bar at the top
/// edge remains. F11 toggles it.
class ConsolePage extends StatefulWidget {
  const ConsolePage({super.key, required this.config, required this.title, required this.url});

  final ServerConfig config;
  final String title;
  final Uri url;

  @override
  State<ConsolePage> createState() => _ConsolePageState();
}

class _ConsolePageState extends State<ConsolePage> {
  bool _full = false;

  Future<void> _setFull(bool value) async {
    if (isDesktop) {
      try {
        await windowManager.setFullScreen(value);
      } catch (_) {
        // Still hide the app's own bars even if the window call fails.
      }
    }
    if (mounted) setState(() => _full = value);
  }

  Future<void> _close() async {
    if (_full) await _setFull(false);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    if (_full && isDesktop) windowManager.setFullScreen(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _full
          ? null
          : AppBar(
              title: Text(widget.title),
              actions: [
                IconButton(
                  tooltip: 'Full screen (F11)',
                  icon: const Icon(Icons.fullscreen),
                  onPressed: () => _setFull(true),
                ),
                const SizedBox(width: 8),
              ],
            ),
      body: Stack(
        children: [
          Positioned.fill(
            child: WebPane(
              config: widget.config,
              url: widget.url,
              showToolbar: !_full,
              onToggleFullScreen: () => _setFull(!_full),
            ),
          ),
          if (_full)
            Align(
              alignment: Alignment.topCenter,
              child: _ConnectionBar(
                title: widget.title,
                onExitFullScreen: () => _setFull(false),
                onClose: _close,
              ),
            ),
        ],
      ),
    );
  }
}

/// The small bar at the top of a full screen console. Faint until the mouse
/// is over it, so it stays out of the way of the guest's screen.
class _ConnectionBar extends StatefulWidget {
  const _ConnectionBar({
    required this.title,
    required this.onExitFullScreen,
    required this.onClose,
  });

  final String title;
  final VoidCallback onExitFullScreen;
  final VoidCallback onClose;

  @override
  State<_ConnectionBar> createState() => _ConnectionBarState();
}

class _ConnectionBarState extends State<_ConnectionBar> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedOpacity(
        opacity: _hover ? 1 : 0.35,
        duration: const Duration(milliseconds: 150),
        child: Material(
          color: scheme.surfaceContainerHighest,
          elevation: 4,
          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Exit full screen (F11)',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.fullscreen_exit, size: 20),
                  onPressed: widget.onExitFullScreen,
                ),
                IconButton(
                  tooltip: 'Close console',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: widget.onClose,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
