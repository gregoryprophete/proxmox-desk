import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Everything the app needs to reach one Proxmox server.
class ServerConfig {
  const ServerConfig({
    required this.host,
    required this.port,
    this.tokenId = '',
    this.tokenSecret = '',
    this.fingerprint = '',
  });

  final String host;
  final int port;

  /// API token ID, for example `root@pam!desk`. Empty when not set.
  final String tokenId;
  final String tokenSecret;

  /// SHA-256 fingerprint of the server certificate the user accepted.
  /// Empty when the certificate is already trusted by the system.
  final String fingerprint;

  bool get hasToken => tokenId.isNotEmpty && tokenSecret.isNotEmpty;

  Uri get baseUri => Uri(scheme: 'https', host: host, port: port);

  Uri webUri([Map<String, String>? query]) =>
      Uri(scheme: 'https', host: host, port: port, path: '/', queryParameters: query);
}

/// Host details go in normal preferences; the token secret goes in the
/// operating system's credential store.
class ConfigStore {
  static const _secure = FlutterSecureStorage();
  static const _secretKey = 'proxmox_token_secret';

  static Future<ServerConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('host');
    if (host == null || host.isEmpty) return null;
    String secret = '';
    try {
      secret = await _secure.read(key: _secretKey) ?? '';
    } catch (_) {
      // Credential store unavailable: carry on without a token.
    }
    return ServerConfig(
      host: host,
      port: prefs.getInt('port') ?? 8006,
      tokenId: prefs.getString('tokenId') ?? '',
      tokenSecret: secret,
      fingerprint: prefs.getString('fingerprint') ?? '',
    );
  }

  static Future<void> save(ServerConfig c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', c.host);
    await prefs.setInt('port', c.port);
    await prefs.setString('tokenId', c.tokenId);
    await prefs.setString('fingerprint', c.fingerprint);
    if (c.tokenSecret.isEmpty) {
      await _secure.delete(key: _secretKey);
    } else {
      await _secure.write(key: _secretKey, value: c.tokenSecret);
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in ['host', 'port', 'tokenId', 'fingerprint']) {
      await prefs.remove(k);
    }
    await _secure.delete(key: _secretKey);
  }
}
