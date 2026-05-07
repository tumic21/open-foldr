import 'dart:convert';
import 'dart:io';

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
  static File _storageFile() {
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

  static Future<ClientIdentity> load() async {
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

    final id = const Uuid().v4();
    final host = Platform.localHostname.trim();
    final fallback = 'Client-${id.substring(0, 8)}';
    final name = host.isEmpty ? fallback : host;
    final identity = ClientIdentity(id: id, name: name);

    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(identity.toJson()), flush: true);
    return identity;
  }
}
