import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/role.dart';

/// A client that has been approved by the host and persisted across sessions.
class TrustedClient {
  final String deviceId;
  final String deviceName;
  final String publicKeyFingerprint;
  final Role role;
  final DateTime pairedAt;

  const TrustedClient({
    required this.deviceId,
    required this.deviceName,
    required this.publicKeyFingerprint,
    required this.role,
    required this.pairedAt,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'publicKeyFingerprint': publicKeyFingerprint,
    'role': role.name,
    'pairedAt': pairedAt.toUtc().toIso8601String(),
  };

  factory TrustedClient.fromJson(Map<String, dynamic> j) => TrustedClient(
    deviceId: j['deviceId'] as String,
    deviceName: j['deviceName'] as String,
    publicKeyFingerprint: j['publicKeyFingerprint'] as String? ?? '',
    role: Role.values.firstWhere(
      (r) => r.name == j['role'],
      orElse: () => Role.viewer,
    ),
    pairedAt: DateTime.parse(j['pairedAt'] as String),
  );
}

/// Persists and retrieves the host's list of trusted (remembered) clients.
class TrustedClientStore {
  static const _key = 'trusted_clients';

  static Future<List<TrustedClient>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => TrustedClient.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<TrustedClient> clients) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode(clients.map((c) => c.toJson()).toList()),
    );
  }

  /// Upsert a trusted client by deviceId (update role/name if already stored).
  static Future<void> upsert(TrustedClient client) async {
    final list = await load();
    final idx = list.indexWhere((c) => c.deviceId == client.deviceId);
    if (idx >= 0) {
      list[idx] = client;
    } else {
      list.add(client);
    }
    await save(list);
  }

  /// Remove a trusted client by deviceId.
  static Future<void> remove(String deviceId) async {
    final list = await load();
    list.removeWhere((c) => c.deviceId == deviceId);
    await save(list);
  }

  /// Find a client by deviceId.
  static Future<TrustedClient?> findById(String deviceId) async {
    final list = await load();
    try {
      return list.firstWhere((c) => c.deviceId == deviceId);
    } catch (_) {
      return null;
    }
  }

  /// Find a client by fingerprint (for auto-approve on pair request).
  static Future<TrustedClient?> findByFingerprint(String fingerprint) async {
    if (fingerprint.isEmpty) return null;
    final list = await load();
    try {
      return list.firstWhere((c) => c.publicKeyFingerprint == fingerprint);
    } catch (_) {
      return null;
    }
  }
}
