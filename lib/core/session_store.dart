import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/shared_root.dart';

/// Persists the host's shared folders between sessions.
class SessionStore {
  static const _key = 'last_session_roots';

  /// Load the previously saved roots, filtering out paths that no longer exist.
  static Future<List<SharedRoot>> loadRoots() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => SharedRoot.fromJson(e as Map<String, dynamic>))
          .where((r) => Directory(r.localPath).existsSync())
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Persist the current list of roots.
  static Future<void> saveRoots(List<SharedRoot> roots) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(roots.map((r) => r.toJson()).toList()));
  }
}
