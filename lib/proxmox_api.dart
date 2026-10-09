import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'config.dart';

class ProxmoxException implements Exception {
  const ProxmoxException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Turns low-level errors into something worth showing on screen.
String describeError(Object e) {
  if (e is ProxmoxException) return e.message;
  if (e is TimeoutException) {
    return 'The server did not answer in time. Check the address and that ZeroTier or your network is up.';
  }
  if (e is HandshakeException) {
    return 'The server certificate is not the one you accepted. Open Settings and reconnect to review it.';
  }
  if (e is SocketException) {
    return 'Could not reach the server (${e.message}).';
  }
  return e.toString();
}

/// Colon-separated SHA-256, the same format Proxmox shows under
/// node > System > Certificates.
String fingerprintOf(X509Certificate cert) => sha256
    .convert(cert.der)
    .bytes
    .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
    .join(':');

class CertProbe {
  const CertProbe(this.fingerprint, this.trusted);
  final String fingerprint;

  /// True when the system already trusts the certificate.
  final bool trusted;
}

class Guest {
  Guest.fromJson(Map<String, dynamic> j)
      : vmid = (j['vmid'] as num?)?.toInt() ?? 0,
        name = (j['name'] ?? '') as String,
        node = (j['node'] ?? '') as String,
        type = (j['type'] ?? 'qemu') as String,
        status = (j['status'] ?? 'unknown') as String,
        cpu = (j['cpu'] as num?)?.toDouble() ?? 0,
        maxCpu = (j['maxcpu'] as num?)?.toInt() ?? 0,
        mem = (j['mem'] as num?)?.toInt() ?? 0,
        maxMem = (j['maxmem'] as num?)?.toInt() ?? 0,
        uptime = (j['uptime'] as num?)?.toInt() ?? 0,
        isTemplate = (j['template'] as num?) == 1;

  final int vmid;
  final String name;
  final String node;

  /// `qemu` for a virtual machine, `lxc` for a container.
  final String type;
  final String status;
  final double cpu;
  final int maxCpu;
  final int mem;
  final int maxMem;
  final int uptime;
  final bool isTemplate;

  bool get isContainer => type == 'lxc';
  bool get running => status == 'running';
}

class ProxmoxApi {
  ProxmoxApi(this.config) {
    _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      // Only reached for certificates the system does not trust. Accept
      // exactly the one certificate the user approved, on this host only.
      ..badCertificateCallback = (cert, host, port) =>
          config.fingerprint.isNotEmpty &&
          host == config.host &&
          fingerprintOf(cert) == config.fingerprint;
  }

  final ServerConfig config;
  late final HttpClient _client;

  void close() => _client.close(force: true);

  /// Connects once to read the server certificate, without sending anything.
  static Future<CertProbe> probe(String host, int port) async {
    var untrusted = false;
    final socket = await SecureSocket.connect(
      host,
      port,
      timeout: const Duration(seconds: 8),
      onBadCertificate: (_) {
        untrusted = true;
        return true;
      },
    );
    try {
      final cert = socket.peerCertificate;
      if (cert == null) {
        throw const ProxmoxException('The server did not present a certificate.');
      }
      return CertProbe(fingerprintOf(cert), !untrusted);
    } finally {
      socket.destroy();
    }
  }

  Future<dynamic> _send(String method, String path, {Map<String, String>? query}) async {
    final uri = config.baseUri.replace(path: '/api2/json$path', queryParameters: query);
    final req = await _client.openUrl(method, uri).timeout(const Duration(seconds: 10));
    req.headers.set(
      HttpHeaders.authorizationHeader,
      'PVEAPIToken=${config.tokenId}=${config.tokenSecret}',
    );
    if (method == 'POST') {
      req.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
      req.contentLength = 0;
    }
    final res = await req.close().timeout(const Duration(seconds: 15));
    final body = await res.transform(utf8.decoder).join();
    if (res.statusCode == 401) {
      throw const ProxmoxException('The API token was rejected. Check the token ID and secret.');
    }
    if (res.statusCode == 403) {
      throw ProxmoxException(
          'The API token is not allowed to do that (${res.reasonPhrase}). Give it a role such as PVEVMAdmin.');
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ProxmoxException('Proxmox answered ${res.statusCode}: ${res.reasonPhrase}');
    }
    final decoded = jsonDecode(body);
    return decoded is Map ? decoded['data'] : null;
  }

  Future<String> version() async {
    final data = await _send('GET', '/version');
    return data is Map ? '${data['version'] ?? ''}' : '';
  }

  Future<List<Guest>> guests() async {
    final data = await _send('GET', '/cluster/resources', query: {'type': 'vm'});
    final list = (data as List? ?? const [])
        .whereType<Map>()
        .map((m) => Guest.fromJson(Map<String, dynamic>.from(m)))
        .where((g) => !g.isTemplate)
        .toList()
      ..sort((a, b) => a.vmid.compareTo(b.vmid));
    return list;
  }

  /// [action] is one of start, shutdown, reboot, stop.
  Future<void> power(Guest g, String action) =>
      _send('POST', '/nodes/${g.node}/${g.type}/${g.vmid}/status/$action');
}
