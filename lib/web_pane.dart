import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'config.dart';

/// Set in main(). False on Windows when the WebView2 runtime is missing.
bool webViewAvailable = true;

/// The Proxmox web interface (or one of its console pages) inside the app.
class WebPane extends StatefulWidget {
  const WebPane({super.key, required this.config, this.url});

  final ServerConfig config;

  /// Page to open. Defaults to the web interface home.
  final Uri? url;

  @override
  State<WebPane> createState() => _WebPaneState();
}

class _WebPaneState extends State<WebPane> {
  InAppWebViewController? _controller;
  double _progress = 0;
  String? _error;

  Uri get _start => widget.url ?? widget.config.webUri();

  void _load(Uri uri) {
    setState(() => _error = null);
    _controller?.loadUrl(urlRequest: URLRequest(url: WebUri.uri(uri)));
  }

  @override
  Widget build(BuildContext context) {
    if (!webViewAvailable) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'The Microsoft Edge WebView2 Runtime is not installed. '
            'Install it from Microsoft, then restart the app.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => _controller?.goBack(),
            ),
            IconButton(
              tooltip: 'Reload',
              icon: const Icon(Icons.refresh),
              onPressed: () {
                setState(() => _error = null);
                _controller?.reload();
              },
            ),
            IconButton(
              tooltip: 'Start page',
              icon: const Icon(Icons.home_outlined),
              onPressed: () => _load(_start),
            ),
            Expanded(
              child: Text(
                '${widget.config.host}:${widget.config.port}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        SizedBox(
          height: 2,
          child: _progress < 1 ? LinearProgressIndicator(value: _progress) : null,
        ),
        if (_error != null)
          MaterialBanner(
            content: Text(_error!),
            actions: [
              TextButton(onPressed: () => _load(_start), child: const Text('Try again')),
            ],
          ),
        Expanded(
          child: InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri.uri(_start)),
            initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
            onWebViewCreated: (c) => _controller = c,
            onProgressChanged: (c, p) {
              if (mounted) setState(() => _progress = p / 100);
            },
            // Proxmox ships with a self-signed certificate. Let it through
            // for the configured server only; every other host keeps the
            // normal browser checks.
            onReceivedServerTrustAuthRequest: (c, challenge) async {
              final sameServer = challenge.protectionSpace.host == widget.config.host &&
                  challenge.protectionSpace.port == widget.config.port;
              return ServerTrustAuthResponse(
                action: sameServer
                    ? ServerTrustAuthResponseAction.PROCEED
                    : ServerTrustAuthResponseAction.CANCEL,
              );
            },
            onReceivedError: (c, request, error) {
              if ((request.isForMainFrame ?? false) && mounted) {
                setState(() => _error = 'Could not load the page: ${error.description}');
              }
            },
          ),
        ),
      ],
    );
  }
}
