import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';
import '../pairing/pairing_manager.dart';
import '../pairing/token_store.dart';
import '../roots/root_registry.dart';
import '../../core/result.dart';
import '../../core/host_identity.dart';
import '../activity/activity_log.dart';
import '../../models/role.dart';

final _uuid = const Uuid();

// ─── Health ──────────────────────────────────────────────────────────────────

Handler healthHandler() {
  return (Request _) => Response.ok(
    jsonEncode({
      'status': 'ok',
      'version': 'v1',
      'host': {'id': HostIdentity.id, 'name': HostIdentity.name},
    }),
    headers: _json,
  );
}

// ─── Pairing ─────────────────────────────────────────────────────────────────

/// Pending pair requests waiting for completion.
final Map<String, PairRequest> _pendingRequests = {};

Handler pairRequestHandler(PairingManager pairing) {
  return (Request request) async {
    final ip = _clientIp(request);
    if (pairing.isLockedOut(ip)) {
      return _error(429, 'RATE_LIMITED', 'Too many attempts. Try later.');
    }

    final body = await _parseJson(request);
    if (body == null) return _error(400, 'INVALID_ARGUMENT', 'Invalid JSON');

    final deviceName = body['deviceName'] as String?;
    final fingerprint = body['devicePublicKey'] as String? ?? '';
    final secret = body['pairingSecret'] as String?;

    if (deviceName == null || secret == null) {
      return _error(
        400,
        'INVALID_ARGUMENT',
        'deviceName and pairingSecret are required',
      );
    }

    final err = pairing.validate(ip, secret);
    if (err != null) {
      final status = err == 'RATE_LIMITED' ? 429 : 401;
      return _error(status, err, 'Pairing validation failed: $err');
    }

    final requestId = _uuid.v4();
    _pendingRequests[requestId] = PairRequest(
      id: requestId,
      deviceName: deviceName,
      fingerprint: fingerprint,
      ip: ip,
    )..approved = true;

    return Response.ok(
      jsonEncode({'pairRequestId': requestId, 'approval': 'auto'}),
      headers: _json,
    );
  };
}

Handler pairCompleteHandler(TokenStore tokens) {
  return (Request request) async {
    final body = await _parseJson(request);
    if (body == null) return _error(400, 'INVALID_ARGUMENT', 'Invalid JSON');

    final requestId = body['pairRequestId'] as String?;
    if (requestId == null) {
      return _error(400, 'INVALID_ARGUMENT', 'pairRequestId required');
    }

    final pending = _pendingRequests[requestId];
    if (pending == null) {
      return _error(
        404,
        'NOT_FOUND',
        'Pair request not found or already consumed',
      );
    }

    final result = tokens.issue(
      deviceId: _uuid.v4(),
      deviceName: pending.deviceName,
      publicKeyFingerprint: pending.fingerprint,
      role: pending.role,
    );

    // Consume request after successful completion.
    _pendingRequests.remove(requestId);

    return Response.ok(
      jsonEncode({
        'sessionToken': result.sessionToken,
        'expiresAt': result.expiresAt.toUtc().toIso8601String(),
        'deviceToken': result.deviceToken,
        'role': pending.role.name,
      }),
      headers: _json,
    );
  };
}

Handler tokenRefreshHandler(TokenStore tokens) {
  return (Request request) async {
    final body = await _parseJson(request);
    if (body == null) return _error(400, 'INVALID_ARGUMENT', 'Invalid JSON');

    final deviceToken = body['deviceToken'] as String?;
    if (deviceToken == null) {
      return _error(400, 'INVALID_ARGUMENT', 'deviceToken required');
    }

    final result = tokens.refresh(deviceToken);
    if (result == null) {
      return _error(401, 'UNAUTHORIZED', 'Device token invalid or revoked');
    }

    return Response.ok(
      jsonEncode({
        'sessionToken': result.sessionToken,
        'expiresAt': result.expiresAt.toUtc().toIso8601String(),
      }),
      headers: _json,
    );
  };
}

/// Approves a pending pair request from the host side (called from UI layer).
void approvePairRequest(String requestId, {Role role = Role.viewer}) {
  final req = _pendingRequests[requestId];
  if (req != null) {
    req.approved = true;
    req.role = role;
  }
}

/// Denies a pending pair request.
void denyPairRequest(String requestId) {
  _pendingRequests.remove(requestId);
}

/// Returns all pending requests (for host UI).
List<PairRequest> get pendingPairRequests => _pendingRequests.values.toList();

// ─── Roots ────────────────────────────────────────────────────────────────────

Handler rootsListHandler(RootRegistry registry) {
  return (Request request) {
    final roots = registry.all
        .map((r) => {'alias': r.alias, 'minimumRole': r.minimumRole.name})
        .toList();
    return Response.ok(jsonEncode({'roots': roots}), headers: _json);
  };
}

Handler entriesHandler(RootRegistry registry, ActivityLog log) {
  return (Request request) async {
    final alias = request.params['alias']!;
    final root = registry.get(alias);
    if (root == null) return _error(404, 'NOT_FOUND', 'Root not found');

    final guard = registry.guard(alias)!;
    final rawPath = request.url.queryParameters['path'] ?? '/';
    final resolved = guard.resolve(_stripLeadingSlash(rawPath));
    if (resolved.isErr) {
      return _error(400, resolved.errorCode, resolved.errorMessage);
    }

    final dir = Directory(resolved.unwrap);
    if (!dir.existsSync()) {
      return _error(404, 'NOT_FOUND', 'Path not found');
    }

    final entries = <Map<String, dynamic>>[];
    for (final entity in dir.listSync()) {
      final stat = entity.statSync();
      final name = entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
      final relPath = p.posix.normalize(p.posix.join(rawPath, name));
      entries.add({
        'name': name,
        'kind': entity is Directory ? 'directory' : 'file',
        'size': stat.size,
        'modifiedAt': stat.modified.toUtc().toIso8601String(),
        'path': relPath.startsWith('/') ? relPath : '/$relPath',
      });
    }

    return Response.ok(
      jsonEncode({'entries': entries, 'path': rawPath}),
      headers: _json,
    );
  };
}

Handler fileDownloadHandler(RootRegistry registry, ActivityLog log) {
  return (Request request) async {
    final alias = request.params['alias']!;
    final root = registry.get(alias);
    if (root == null) return _error(404, 'NOT_FOUND', 'Root not found');

    final guard = registry.guard(alias)!;
    final rawPath = request.url.queryParameters['path'] ?? '';
    if (rawPath.isEmpty) {
      return _error(400, 'INVALID_ARGUMENT', 'path is required');
    }

    final resolved = guard.resolve(_stripLeadingSlash(rawPath));
    if (resolved.isErr) {
      return _error(400, resolved.errorCode, resolved.errorMessage);
    }

    final file = File(resolved.unwrap);
    if (!file.existsSync()) {
      return _error(404, 'NOT_FOUND', 'File not found');
    }

    final fileSize = file.lengthSync();
    final rangeHeader = request.headers['range'];

    // ── Range request (resumable download) ─────────────────────────────────
    if (rangeHeader != null) {
      final range = _parseRange(rangeHeader, fileSize);
      if (range == null) {
        return Response(
          416,
          headers: {
            'content-range': 'bytes */$fileSize',
            'content-type': 'application/json',
          },
          body: jsonEncode({
            'error': {
              'code': 'RANGE_NOT_SATISFIABLE',
              'message': 'Invalid Range header',
            },
          }),
        );
      }
      final (start, end) = range;
      final length = end - start + 1;
      return Response(
        206,
        body: file.openRead(start, end + 1),
        headers: {
          'content-type': 'application/octet-stream',
          'content-range': 'bytes $start-$end/$fileSize',
          'content-length': '$length',
          'accept-ranges': 'bytes',
        },
      );
    }

    // ── Full download ───────────────────────────────────────────────────────
    return Response.ok(
      file.openRead(),
      headers: {
        'content-type': 'application/octet-stream',
        'content-length': '$fileSize',
        'accept-ranges': 'bytes',
      },
    );
  };
}

Handler fileMetadataHandler(RootRegistry registry) {
  return (Request request) async {
    final alias = request.params['alias']!;
    final root = registry.get(alias);
    if (root == null) return _error(404, 'NOT_FOUND', 'Root not found');

    final guard = registry.guard(alias)!;
    final rawPath = request.url.queryParameters['path'] ?? '';
    if (rawPath.isEmpty) {
      return _error(400, 'INVALID_ARGUMENT', 'path is required');
    }

    final resolved = guard.resolve(_stripLeadingSlash(rawPath));
    if (resolved.isErr) {
      return _error(400, resolved.errorCode, resolved.errorMessage);
    }

    final file = File(resolved.unwrap);
    if (!file.existsSync()) {
      return _error(404, 'NOT_FOUND', 'File not found');
    }

    final stat = file.statSync();
    final versionToken = _computeVersionToken(stat);
    return Response.ok(
      jsonEncode({
        'size': stat.size,
        'modifiedAt': stat.modified.toUtc().toIso8601String(),
        'versionToken': versionToken,
      }),
      headers: _json,
    );
  };
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

const _json = {'content-type': 'application/json'};

/// Computes a lightweight version token from file stat fields.
/// Does not read file content — uses last-modified time and size as etag.
String _computeVersionToken(FileStat stat) {
  final raw = '${stat.modified.microsecondsSinceEpoch}-${stat.size}';
  return sha256.convert(utf8.encode(raw)).toString().substring(0, 16);
}

/// Public alias used by write handlers in the same package.
String computeVersionToken(FileStat stat) => _computeVersionToken(stat);

/// Strips the leading '/' from API paths before passing to PathGuard,
/// which expects relative paths (not absolute).
String stripLeadingSlash(String path) {
  if (path.startsWith('/')) return path.substring(1);
  return path;
}

// ignore: unused_element
String _stripLeadingSlash(String path) => stripLeadingSlash(path);

String _clientIp(Request request) =>
    request.headers['x-forwarded-for'] ??
    request.headers['x-real-ip'] ??
    '0.0.0.0';

Future<Map<String, dynamic>?> _parseJson(Request request) async {
  try {
    final body = await request.readAsString();
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

Response _error(int status, String code, String message) => Response(
  status,
  headers: _json,
  body: jsonEncode({
    'error': {'code': code, 'message': message},
  }),
);

class PairRequest {
  final String id;
  final String deviceName;
  final String fingerprint;
  final String ip;
  bool approved = false;
  Role role = Role.viewer;

  PairRequest({
    required this.id,
    required this.deviceName,
    required this.fingerprint,
    required this.ip,
  });
}

/// Parses a `Range: bytes=<start>-<end>` header.
/// Returns (start, end) inclusive, clamped to [0, fileSize-1].
/// Returns null if the header is malformed or unsatisfiable.
(int, int)? _parseRange(String header, int fileSize) {
  if (fileSize == 0) return null;
  final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
  if (match == null) return null;
  final startStr = match.group(1)!;
  final endStr = match.group(2)!;

  int start;
  int end;

  if (startStr.isEmpty && endStr.isEmpty) return null;

  if (startStr.isEmpty) {
    // Suffix range: bytes=-N  (last N bytes)
    final n = int.tryParse(endStr);
    if (n == null || n <= 0) return null;
    start = fileSize - n < 0 ? 0 : fileSize - n;
    end = fileSize - 1;
  } else {
    start = int.tryParse(startStr) ?? -1;
    end = endStr.isEmpty ? fileSize - 1 : (int.tryParse(endStr) ?? -1);
    if (start < 0 || end < 0) return null;
    if (end >= fileSize) end = fileSize - 1;
    if (start > end) return null;
  }

  return (start, end);
}
