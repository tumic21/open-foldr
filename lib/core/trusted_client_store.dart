import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

/// A client that has been approved by the host and persisted across sessions.
class TrustedClient {
  final String deviceId;
  final String deviceName;
  final String publicKeyFingerprint;
  final DateTime pairedAt;

  const TrustedClient({
    required this.deviceId,
    required this.deviceName,
    required this.publicKeyFingerprint,
    required this.pairedAt,
  });

  Map<String, dynamic> toJson() => {
    'deviceId': deviceId,
    'deviceName': deviceName,
    'publicKeyFingerprint': publicKeyFingerprint,
    'pairedAt': pairedAt.toUtc().toIso8601String(),
  };

  factory TrustedClient.fromJson(Map<String, dynamic> j) => TrustedClient(
    deviceId: j['deviceId'] as String,
    deviceName: j['deviceName'] as String,
    publicKeyFingerprint: j['publicKeyFingerprint'] as String? ?? '',
    pairedAt: DateTime.parse(j['pairedAt'] as String),
  );
}

/// Persists and retrieves the host's list of trusted (remembered) clients.
class TrustedClientStore {
  static const _prefsKey = 'trusted_clients';

  static String _encodeClients(List<TrustedClient> clients) {
    return jsonEncode(clients.map((c) => c.toJson()).toList());
  }

  static File _storageFile() {
    final isTest =
        Platform.environment.containsKey('FLUTTER_TEST') ||
        Platform.environment.containsKey('DART_TEST');

    if (isTest) {
      return File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}open_foldr_test${Platform.pathSeparator}trusted_clients.json',
      );
    }

    if (Platform.isWindows) {
      final base =
          Platform.environment['APPDATA'] ??
          Platform.environment['USERPROFILE'];
      if (base != null && base.isNotEmpty) {
        return File(
          '$base${Platform.pathSeparator}OpenFoldr${Platform.pathSeparator}trusted_clients.json',
        );
      }
    }

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return File(
        '$home${Platform.pathSeparator}.open_foldr${Platform.pathSeparator}trusted_clients.json',
      );
    }

    return File(
      '${Directory.current.path}${Platform.pathSeparator}.open_foldr${Platform.pathSeparator}trusted_clients.json',
    );
  }

  static Future<List<TrustedClient>> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return [];
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => TrustedClient.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<List<TrustedClient>> load() async {
    final file = _storageFile();
    try {
      if (await file.exists()) {
        final raw = await file.readAsString();
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .map((e) => TrustedClient.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {
      // Fall through to preference fallback.
    }

    // Fallback + one-time migration path.
    final migrated = await _loadFromPrefs();
    if (migrated.isNotEmpty) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(_encodeClients(migrated), flush: true);
      } catch (_) {
        // Ignore file migration failures on constrained platforms.
      }
    }
    return migrated;
  }

  static Future<void> save(List<TrustedClient> clients) async {
    final file = _storageFile();
    final encoded = _encodeClients(clients);

    // Prefer file storage, but don't fail the overall save if this errors.
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(encoded, flush: true);
    } catch (_) {
      // Ignore file write failures and keep prefs as durable fallback.
    }

    // Keep legacy storage best-effort for compatibility.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, encoded);
    } catch (_) {
      // Ignore preference write failures.
    }
  }

  static Future<void> clear() async {
    final file = _storageFile();
    if (await file.exists()) {
      await file.delete();
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKey);
    } catch (_) {
      // Ignore preference clear failures.
    }
  }

  /// Upsert a trusted client by deviceId (update metadata if already stored).
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
