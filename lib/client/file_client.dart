import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import '../core/client_identity_store.dart';
import '../core/result.dart';
export '../core/result.dart';

/// A typed HTTP client for talking to an OpenFoldr host server.
///
/// All methods return [Result<T>]: [Ok] on success, [Err] with a server error
/// code and human-readable message on failure.
///
/// Obtain a connected instance via [FileClient.pair].  Call [close] when done
/// to release the underlying HTTP connection pool.
class FileClient {
  final String baseUrl;
  final String sessionToken;
  final http.Client _http;

  FileClient({
    required this.baseUrl,
    required this.sessionToken,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  /// Release the underlying HTTP connection pool.
  void close() => _http.close();

  // ─── Pairing (static factory) ────────────────────────────────────────────

  /// Executes the two-step pairing handshake against [baseUrl] using
  /// [pairingSecret] and [deviceId] (if reconnecting a known device)
  /// and returns a ready-to-use [FileClient] plus the negotiated [PairData].
  static Future<Result<PairData>> pair({
    required String baseUrl,
    required String pairingSecret,
    String? deviceId,
    String? clientName,
    String? clientFingerprint,
    http.Client? httpClient,
  }) async {
    final rawHttp = httpClient ?? http.Client();
    try {
      final identity = await ClientIdentityStore.load();

      // Step 1 — request pairing.
      final reqRes = await rawHttp.post(
        Uri.parse('$baseUrl/auth/pair/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'deviceName': clientName ?? identity.name,
          'devicePublicKey': clientFingerprint ?? identity.id,
          'pairingSecret': pairingSecret,
          if (deviceId != null) 'deviceId': deviceId,
        }),
      );
      if (reqRes.statusCode != 200) {
        return _errFromResponse<PairData>(reqRes);
      }
      final requestId =
          (jsonDecode(reqRes.body) as Map<String, dynamic>)['pairRequestId']
              as String;

      // Step 2 — complete pairing.
      final completeRes = await rawHttp.post(
        Uri.parse('$baseUrl/auth/pair/complete'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'pairRequestId': requestId}),
      );
      if (completeRes.statusCode != 200) {
        return _errFromResponse<PairData>(completeRes);
      }
      final completeBody = jsonDecode(completeRes.body) as Map<String, dynamic>;
      final token = completeBody['sessionToken'] as String;
      final role = completeBody['role'] as String? ?? 'viewer';
      final returnedDeviceToken = completeBody['deviceToken'] as String? ?? '';
      final returnedDeviceId = completeBody['deviceId'] as String? ?? '';

      final client = FileClient(
        baseUrl: baseUrl,
        sessionToken: token,
        httpClient: rawHttp,
      );
      return Ok(
        PairData(
          client: client,
          sessionToken: token,
          role: role,
          deviceToken: returnedDeviceToken,
          deviceId: returnedDeviceId,
        ),
      );
    } catch (e) {
      rawHttp.close();
      return Err('NETWORK_ERROR', e.toString());
    }
  }

  /// Tries to re-establish a session using a previously issued [deviceToken].
  /// Returns [Ok(PairData)] on success, or an [Err] if the token is invalid.
  static Future<Result<PairData>> reconnect({
    required String baseUrl,
    required String deviceToken,
    required String deviceId,
    http.Client? httpClient,
  }) async {
    final rawHttp = httpClient ?? http.Client();
    try {
      final res = await rawHttp.post(
        Uri.parse('$baseUrl/auth/token/refresh'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'deviceToken': deviceToken}),
      );
      if (res.statusCode != 200) {
        rawHttp.close();
        return _errFromResponse<PairData>(res);
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final sessionToken = body['sessionToken'] as String;

      // Fetch current role.
      final client = FileClient(
        baseUrl: baseUrl,
        sessionToken: sessionToken,
        httpClient: rawHttp,
      );
      String role = 'viewer';
      final roleResult = await client.getSessionRole();
      if (roleResult.isOk) role = roleResult.unwrap;

      return Ok(
        PairData(
          client: client,
          sessionToken: sessionToken,
          role: role,
          deviceToken: deviceToken,
          deviceId: deviceId,
        ),
      );
    } catch (e) {
      rawHttp.close();
      return Err('NETWORK_ERROR', e.toString());
    }
  }

  // ─── Roots listing ───────────────────────────────────────────────────────

  Future<Result<String>> getSessionRole() async {
    final uri = Uri.parse('$baseUrl/session');
    try {
      final res = await _http.get(uri, headers: _authHeaders());
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return Ok(body['role'] as String? ?? 'viewer');
      }
      return _errFromBody(res);
    } catch (e) {
      return Err('NETWORK_ERROR', e.toString());
    }
  }

  /// Lists the shared roots available on the host.
  Future<Result<List<Map<String, dynamic>>>> listRoots() async {
    final uri = Uri.parse('$baseUrl/roots');
    try {
      final res = await _http.get(uri, headers: _authHeaders());
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final roots = List<Map<String, dynamic>>.from(body['roots'] as List);
        return Ok(roots);
      }
      return _errFromBody(res);
    } catch (e) {
      return Err('NETWORK_ERROR', e.toString());
    }
  }

  // ─── Directory listing ──────────────────────────────────────────────────

  /// Lists entries (files and sub-directories) at [path] under [alias].
  Future<Result<List<FileEntry>>> listEntries(String alias, String path) async {
    final uri = Uri.parse(
      '$baseUrl/roots/$alias/entries',
    ).replace(queryParameters: {'path': path});
    try {
      final res = await _http.get(uri, headers: _authHeaders());
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = (body['entries'] as List)
            .cast<Map<String, dynamic>>()
            .map(FileEntry.fromJson)
            .toList();
        return Ok(list);
      }
      return _errFromBody(res);
    } catch (e) {
      return Err('NETWORK_ERROR', e.toString());
    }
  }

  // ─── File download ───────────────────────────────────────────────────────

  /// Downloads the file at [path] under [alias] and returns its raw bytes.
  Future<Result<Uint8List>> downloadFile(String alias, String path) async {
    final uri = Uri.parse(
      '$baseUrl/roots/$alias/file',
    ).replace(queryParameters: {'path': path});
    try {
      final res = await _http.get(uri, headers: _authHeaders());
      if (res.statusCode == 200) return Ok(res.bodyBytes);
      return _errFromBody(res);
    } catch (e) {
      return Err('NETWORK_ERROR', e.toString());
    }
  }

  // ─── Metadata ───────────────────────────────────────────────────────────

  /// Returns metadata (including the current `versionToken`) for a file.
  Future<Result<FileMetadata>> getMetadata(String alias, String path) async {
    final uri = Uri.parse(
      '$baseUrl/roots/$alias/metadata',
    ).replace(queryParameters: {'path': path});
    try {
      final res = await _http.get(uri, headers: _authHeaders());
      if (res.statusCode == 200) {
        return Ok(
          FileMetadata.fromJson(jsonDecode(res.body) as Map<String, dynamic>),
        );
      }
      return _errFromBody(res);
    } catch (e) {
      return Err('NETWORK_ERROR', e.toString());
    }
  }

  // ─── File upload ─────────────────────────────────────────────────────────

  /// Creates or replaces the file at [path] under [alias].
  ///
  /// For updates, [ifMatch] must contain the current `versionToken`
  /// (obtained from [getMetadata]).  Pass `'*'` to force-overwrite (owner
  /// only).  Omit [ifMatch] when creating a new file.
  ///
  /// Returns the new `versionToken` on success.
  Future<Result<String>> uploadFile(
    String alias,
    String path,
    Uint8List bytes, {
    String? ifMatch,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/roots/$alias/file',
    ).replace(queryParameters: {'path': path});
    final headers = _authHeaders()
      ..['content-type'] = 'application/octet-stream';
    if (ifMatch != null) headers['if-match'] = ifMatch;
    try {
      final res = await _http.put(uri, headers: headers, body: bytes);
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        return Ok(body['versionToken'] as String);
      }
      return _errFromBody(res);
    } catch (e) {
      return Err('NETWORK_ERROR', e.toString());
    }
  }

  // ─── Delete ──────────────────────────────────────────────────────────────

  /// Deletes a file or directory (recursively) at [path] under [alias].
  Future<Result<void>> deleteItem(String alias, String path) async {
    final uri = Uri.parse(
      '$baseUrl/roots/$alias/file',
    ).replace(queryParameters: {'path': path});
    try {
      final res = await _http.delete(uri, headers: _authHeaders());
      if (res.statusCode == 200) return const Ok(null);
      return _errFromBody(res);
    } catch (e) {
      return Err('NETWORK_ERROR', e.toString());
    }
  }

  /// Deletes multiple paths in a single request.
  ///
  /// Returns a list of per-item [BatchResult] entries.  HTTP 200 means all
  /// succeeded; 207 means some failed — inspect each [BatchResult.status].
  Future<Result<List<BatchResult>>> batchDelete(
    String alias,
    List<String> paths,
  ) async {
    final uri = Uri.parse('$baseUrl/roots/$alias/batch/delete');
    try {
      final res = await _http.post(
        uri,
        headers: _jsonAuthHeaders(),
        body: jsonEncode({'paths': paths}),
      );
      if (res.statusCode == 200 || res.statusCode == 207) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final results = (body['results'] as List)
            .cast<Map<String, dynamic>>()
            .map(BatchResult.fromDeleteJson)
            .toList();
        return Ok(results);
      }
      return _errFromBody(res);
    } catch (e) {
      return Err('NETWORK_ERROR', e.toString());
    }
  }

  // ─── Filesystem operations (Phase 1 server endpoints) ────────────────────

  /// Creates a directory at [path] under [alias].
  Future<Result<void>> mkdir(String alias, String path) async {
    final uri = Uri.parse('$baseUrl/roots/$alias/mkdir');
    try {
      final res = await _http.post(
        uri,
        headers: _jsonAuthHeaders(),
        body: jsonEncode({'path': path}),
      );
      if (res.statusCode == 201) return const Ok(null);
      return _errFromBody(res);
    } catch (e) {
      return Err('NETWORK_ERROR', e.toString());
    }
  }

  /// Renames (or moves) a single item within the same root.
  ///
  /// [from] and [to] are root-relative paths.
  Future<Result<void>> rename(String alias, String from, String to) async {
    final uri = Uri.parse('$baseUrl/roots/$alias/rename');
    try {
      final res = await _http.post(
        uri,
        headers: _jsonAuthHeaders(),
        body: jsonEncode({'from': from, 'to': to}),
      );
      if (res.statusCode == 200) return const Ok(null);
      return _errFromBody(res);
    } catch (e) {
      return Err('NETWORK_ERROR', e.toString());
    }
  }

  /// Copies a single item within the same root.
  ///
  /// Returns `ALREADY_EXISTS` (409) if [to] already exists.
  Future<Result<void>> copy(String alias, String from, String to) async {
    final uri = Uri.parse('$baseUrl/roots/$alias/copy');
    try {
      final res = await _http.post(
        uri,
        headers: _jsonAuthHeaders(),
        body: jsonEncode({'from': from, 'to': to}),
      );
      if (res.statusCode == 201) return const Ok(null);
      return _errFromBody(res);
    } catch (e) {
      return Err('NETWORK_ERROR', e.toString());
    }
  }

  /// Moves multiple items into [destination] directory.
  ///
  /// Returns per-item [BatchResult] entries; HTTP 207 signals partial failure.
  Future<Result<List<BatchResult>>> batchMove(
    String alias,
    List<String> items,
    String destination,
  ) async {
    final uri = Uri.parse('$baseUrl/roots/$alias/batch/move');
    try {
      final res = await _http.post(
        uri,
        headers: _jsonAuthHeaders(),
        body: jsonEncode({'items': items, 'destination': destination}),
      );
      if (res.statusCode == 200 || res.statusCode == 207) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final results = (body['results'] as List)
            .cast<Map<String, dynamic>>()
            .map(BatchResult.fromItemJson)
            .toList();
        return Ok(results);
      }
      return _errFromBody(res);
    } catch (e) {
      return Err('NETWORK_ERROR', e.toString());
    }
  }

  /// Copies multiple items into [destination] directory.
  ///
  /// Returns per-item [BatchResult] entries; HTTP 207 signals partial failure.
  Future<Result<List<BatchResult>>> batchCopy(
    String alias,
    List<String> items,
    String destination,
  ) async {
    final uri = Uri.parse('$baseUrl/roots/$alias/batch/copy');
    try {
      final res = await _http.post(
        uri,
        headers: _jsonAuthHeaders(),
        body: jsonEncode({'items': items, 'destination': destination}),
      );
      if (res.statusCode == 200 || res.statusCode == 207) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final results = (body['results'] as List)
            .cast<Map<String, dynamic>>()
            .map(BatchResult.fromItemJson)
            .toList();
        return Ok(results);
      }
      return _errFromBody(res);
    } catch (e) {
      return Err('NETWORK_ERROR', e.toString());
    }
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  Map<String, String> _authHeaders() => {
    'authorization': 'Bearer $sessionToken',
  };

  Map<String, String> _jsonAuthHeaders() => {
    'authorization': 'Bearer $sessionToken',
    'content-type': 'application/json',
  };

  /// Extracts a typed [Err] from a non-2xx HTTP response body.
  Err<T> _errFromBody<T>(http.Response res) => _errFromResponse<T>(res);

  static Err<T> _errFromResponse<T>(http.Response res) {
    try {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final err = body['error'] as Map<String, dynamic>?;
      final code = err?['code'] as String? ?? 'SERVER_ERROR';
      final message = err?['message'] as String? ?? 'HTTP ${res.statusCode}';
      return Err(code, message);
    } catch (_) {
      return Err('SERVER_ERROR', 'HTTP ${res.statusCode}');
    }
  }
}

// ─── Data models ─────────────────────────────────────────────────────────────

/// Returned by [FileClient.pair] on successful pairing.
class PairData {
  /// A ready-to-use [FileClient] authenticated with [sessionToken].
  final FileClient client;
  final String sessionToken;

  /// Persistent device token (for reconnecting without re-pairing).
  final String deviceToken;

  /// Stable device id issued by the host.
  final String deviceId;

  /// The role assigned to this session by the host ('viewer'|'editor'|'owner').
  final String role;

  const PairData({
    required this.client,
    required this.sessionToken,
    required this.role,
    this.deviceToken = '',
    this.deviceId = '',
  });
}

/// A single directory entry returned by [FileClient.listEntries].
class FileEntry {
  final String name;
  final String path;
  final String kind; // 'file' | 'directory'
  final int size;
  final DateTime modifiedAt;

  const FileEntry({
    required this.name,
    required this.path,
    required this.kind,
    required this.size,
    required this.modifiedAt,
  });

  bool get isDirectory => kind == 'directory';
  bool get isFile => kind == 'file';

  factory FileEntry.fromJson(Map<String, dynamic> json) => FileEntry(
    name: json['name'] as String,
    path: json['path'] as String,
    kind: json['kind'] as String,
    size: json['size'] as int? ?? 0,
    modifiedAt: DateTime.parse(json['modifiedAt'] as String),
  );
}

/// Metadata for a single file (includes the conflict-detection token).
class FileMetadata {
  final String path;
  final int size;
  final DateTime modifiedAt;
  final String versionToken;

  const FileMetadata({
    required this.path,
    required this.size,
    required this.modifiedAt,
    required this.versionToken,
  });

  factory FileMetadata.fromJson(Map<String, dynamic> json) => FileMetadata(
    path: json['path'] as String? ?? '',
    size: json['size'] as int? ?? 0,
    modifiedAt: DateTime.parse(
      json['modifiedAt'] as String? ?? DateTime.now().toIso8601String(),
    ),
    versionToken: json['versionToken'] as String,
  );
}

/// A single item result inside a batch operation response.
class BatchResult {
  /// The path or item identifier that was operated on.
  final String key;
  final int status;
  final String message;

  const BatchResult({
    required this.key,
    required this.status,
    required this.message,
  });

  bool get isSuccess => status == 200 || status == 201;

  /// For batch/delete responses where the key field is `path`.
  factory BatchResult.fromDeleteJson(Map<String, dynamic> json) => BatchResult(
    key: json['path'] as String,
    status: json['status'] as int,
    message: json['message'] as String,
  );

  /// For batch/move and batch/copy responses where the key field is `item`.
  factory BatchResult.fromItemJson(Map<String, dynamic> json) => BatchResult(
    key: json['item'] as String,
    status: json['status'] as int,
    message: json['message'] as String,
  );
}
