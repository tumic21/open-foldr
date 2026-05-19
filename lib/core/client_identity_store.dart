import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class ClientIdentity {
  final String id;
  final String name;

  const ClientIdentity({required this.id, required this.name});

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory ClientIdentity.fromJson(Map<String, dynamic> json) =>
      ClientIdentity(id: json['id'] as String, name: json['name'] as String);
}

/// Stores a stable per-installation client identity used for pairing.
class ClientIdentityStore {
  static const _prefsKey = 'client_identity';

  static File _storageFile() {
    final isTest =
        Platform.environment.containsKey('FLUTTER_TEST') ||
        Platform.environment.containsKey('DART_TEST');

    if (isTest) {
      return File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}open_foldr_test${Platform.pathSeparator}client_identity.json',
      );
    }

    if (Platform.isWindows) {
      final base =
          Platform.environment['APPDATA'] ??
          Platform.environment['USERPROFILE'];
      if (base != null && base.isNotEmpty) {
        return File(
          '$base${Platform.pathSeparator}OpenFoldr${Platform.pathSeparator}client_identity.json',
        );
      }
    }

    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return File(
        '$home${Platform.pathSeparator}.open_foldr${Platform.pathSeparator}client_identity.json',
      );
    }

    return File(
      '${Directory.current.path}${Platform.pathSeparator}.open_foldr${Platform.pathSeparator}client_identity.json',
    );
  }

  static bool get _preferPrefsStorage => Platform.isAndroid || Platform.isIOS;

  static Future<ClientIdentity?> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final id = json['id'] as String?;
      final name = json['name'] as String?;
      if (id == null || id.isEmpty || name == null || name.isEmpty) {
        return null;
      }
      return ClientIdentity(id: id, name: name);
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveToPrefs(ClientIdentity identity) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, jsonEncode(identity.toJson()));
  }

  static ClientIdentity _newIdentity() {
    final id = const Uuid().v4();
    final host = Platform.localHostname.trim();
    final fallback = 'Client-${id.substring(0, 8)}';
    final name = host.isEmpty ? fallback : host;
    return ClientIdentity(id: id, name: name);
  }

  static Future<ClientIdentity> load() async {
    if (_preferPrefsStorage) {
      final fromPrefs = await _loadFromPrefs();
      if (fromPrefs != null) {
        return fromPrefs;
      }
      final identity = _newIdentity();
      await _saveToPrefs(identity);
      return identity;
    }

    final file = _storageFile();
    try {
      if (await file.exists()) {
        final raw = await file.readAsString();
        final json = jsonDecode(raw) as Map<String, dynamic>;
        final id = json['id'] as String?;
        final name = json['name'] as String?;
        if (id != null && id.isNotEmpty && name != null && name.isNotEmpty) {
          return ClientIdentity(id: id, name: name);
        }
      }
    } catch (_) {
      // Fall through to create a new identity.
    }

    final fromPrefs = await _loadFromPrefs();
    if (fromPrefs != null) {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(jsonEncode(fromPrefs.toJson()), flush: true);
      } catch (_) {
        // Ignore file migration failures and keep preferences as fallback.
      }
      return fromPrefs;
    }

    final identity = _newIdentity();
    try {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(identity.toJson()), flush: true);
    } catch (_) {
      // If file persistence fails (e.g. read-only filesystem), persist via prefs.
      await _saveToPrefs(identity);
    }
    return identity;
  }
}
