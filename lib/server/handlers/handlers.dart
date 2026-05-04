import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';
import '../pairing/pairing_manager.dart';
import '../pairing/token_store.dart';
import '../roots/root_registry.dart';
import '../../core/result.dart';
import '../activity/activity_log.dart';
import '../../models/role.dart';

final _uuid = const Uuid();

// ─── Health ──────────────────────────────────────────────────────────────────

Handler healthHandler() {
  return (Request _) => Response.ok(
    jsonEncode({'status': 'ok', 'version': 'v1'}),
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
      final relPath = entity.path.substring(resolved.unwrap.length);
      entries.add({
        'name': entity.uri.pathSegments.lastWhere((s) => s.isNotEmpty),
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

    return Response.ok(
      file.openRead(),
      headers: {'content-type': 'application/octet-stream'},
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
    return Response.ok(
      jsonEncode({
        'size': stat.size,
        'modifiedAt': stat.modified.toUtc().toIso8601String(),
      }),
      headers: _json,
    );
  };
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

const _json = {'content-type': 'application/json'};

/// Strips the leading '/' from API paths before passing to PathGuard,
/// which expects relative paths (not absolute).
String _stripLeadingSlash(String path) {
  if (path.startsWith('/')) return path.substring(1);
  return path;
}

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
