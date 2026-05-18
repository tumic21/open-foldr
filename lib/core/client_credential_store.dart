import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Stores the device token issued by a host so the client can reconnect
/// without re-entering the pairing code.
class ClientCredentialStore {
  static const _key = 'client_credentials';

  /// Load all saved credentials keyed by hostId.
  static Future<Map<String, HostCredential>> _loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map(
        (k, v) =>
            MapEntry(k, HostCredential.fromJson(v as Map<String, dynamic>)),
      );
    } catch (_) {
      return {};
    }
  }

  static Future<void> _saveAll(Map<String, HostCredential> all) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(all.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  /// Save (or update) the device token for a host.
  static Future<void> save({
    required String hostId,
    required String hostName,
    required String hostAddress,
    required int port,
    required String deviceToken,
    required String deviceId,
  }) async {
    final all = await _loadAll();
    all[hostId] = HostCredential(
      hostId: hostId,
      hostName: hostName,
      hostAddress: hostAddress,
      port: port,
      deviceToken: deviceToken,
      deviceId: deviceId,
    );
    await _saveAll(all);
  }

  /// Retrieve credentials for a host by its id.
  static Future<HostCredential?> find(String hostId) async {
    final all = await _loadAll();
    return all[hostId];
  }

  /// Remove credentials for a host (e.g. if revoked).
  static Future<void> remove(String hostId) async {
    final all = await _loadAll();
    all.remove(hostId);
    await _saveAll(all);
  }
}

class HostCredential {
  final String hostId;
  final String hostName;
  final String hostAddress;
  final int port;
  final String deviceToken;
  final String deviceId;

  const HostCredential({
    required this.hostId,
    required this.hostName,
    required this.hostAddress,
    required this.port,
    required this.deviceToken,
    required this.deviceId,
  });

  Map<String, dynamic> toJson() => {
    'hostId': hostId,
    'hostName': hostName,
    'hostAddress': hostAddress,
    'port': port,
    'deviceToken': deviceToken,
    'deviceId': deviceId,
  };

  factory HostCredential.fromJson(Map<String, dynamic> j) => HostCredential(
    hostId: j['hostId'] as String,
    hostName:
        (j['hostName'] as String?) ?? (j['hostAddress'] as String? ?? 'Host'),
    hostAddress: j['hostAddress'] as String,
    port: j['port'] as int,
    deviceToken: j['deviceToken'] as String,
    deviceId: j['deviceId'] as String,
  );
}
