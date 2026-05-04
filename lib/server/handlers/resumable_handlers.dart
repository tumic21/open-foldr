import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';
import '../roots/root_registry.dart';
import '../auth/auth_middleware.dart';
import '../activity/activity_log.dart';
import '../../core/result.dart';
import 'handlers.dart' show computeVersionToken, stripLeadingSlash;

final _uuid = const Uuid();
const _json = {'content-type': 'application/json'};

// ─── In-progress upload state ─────────────────────────────────────────────────

class _UploadSession {
  final String id;
  final String alias;
  final String targetPath;
  final String tmpPath;
  final int totalSize;
  int bytesReceived;
  final DateTime createdAt;

  _UploadSession({
    required this.id,
    required this.alias,
    required this.targetPath,
    required this.tmpPath,
    required this.totalSize,
  })  : bytesReceived = 0,
        createdAt = DateTime.now().toUtc();
}

/// In-memory map of active upload sessions. Key = uploadId.
final Map<String, _UploadSession> _uploads = {};

// ─── POST /v1/roots/<alias>/upload/init ───────────────────────────────────────

/// Initialises a resumable upload.
///
/// Request body:
/// ```json
/// { "path": "/relative/path.bin", "size": 123456 }
/// ```
///
/// Response:
/// ```json
/// { "uploadId": "<uuid>", "offset": 0 }
/// ```
///
/// If a partial upload already exists for the same path the existing
/// `uploadId` and current `offset` are returned so the client can resume.
Handler uploadInitHandler(RootRegistry registry) {
  return (Request request) async {
    final alias = request.params['alias']!;
    if (registry.get(alias) == null) {
      return _error(404, 'NOT_FOUND', 'Root not found');
    }

    final role = roleOf(request);
    if (!role.canWrite()) {
      return _error(403, 'FORBIDDEN', 'Write access required');
    }

    final guard = registry.guard(alias)!;
    final body = await _parseJson(request);
    if (body == null) return _error(400, 'INVALID_ARGUMENT', 'Invalid JSON');

    final rawPath = body['path'] as String?;
    final totalSize = body['size'] as int?;

    if (rawPath == null || totalSize == null) {
      return _error(400, 'INVALID_ARGUMENT', 'path and size are required');
    }
    if (totalSize < 0) {
      return _error(400, 'INVALID_ARGUMENT', 'size must be >= 0');
    }

    final resolved = guard.resolve(stripLeadingSlash(rawPath));
    if (resolved.isErr) {
      return _error(400, resolved.errorCode, resolved.errorMessage);
    }

    final targetPath = resolved.unwrap;

    // Check if a session already exists for this target path — allow resume.
    final existing = _uploads.values
        .where((s) => s.alias == alias && s.targetPath == targetPath)
        .firstOrNull;

    if (existing != null) {
      return Response.ok(
        jsonEncode({
          'uploadId': existing.id,
          'offset': existing.bytesReceived,
        }),
        headers: _json,
      );
    }

    // Create a sibling temp file for the upload.
    final dir = File(targetPath).parent.path;
    Directory(dir).createSync(recursive: true);
    final tmpPath =
        '$dir/.~upload_${Uri.encodeComponent(rawPath)}_${_uuid.v4()}';

    final uploadId = _uuid.v4();
    _uploads[uploadId] = _UploadSession(
      id: uploadId,
      alias: alias,
      targetPath: targetPath,
      tmpPath: tmpPath,
      totalSize: totalSize,
    );

    return Response.ok(
      jsonEncode({'uploadId': uploadId, 'offset': 0}),
      headers: _json,
    );
  };
}

// ─── PATCH /v1/roots/<alias>/upload/<uploadId> ────────────────────────────────

/// Sends a chunk for a resumable upload.
///
/// Required header: `Content-Range: bytes <start>-<end>/<total>`
///
/// Response:
/// ```json
/// { "offset": <total_bytes_received_so_far> }
/// ```
Handler uploadChunkHandler(RootRegistry registry) {
  return (Request request) async {
    final alias = request.params['alias']!;
    if (registry.get(alias) == null) {
      return _error(404, 'NOT_FOUND', 'Root not found');
    }

    final role = roleOf(request);
    if (!role.canWrite()) {
      return _error(403, 'FORBIDDEN', 'Write access required');
    }

    final uploadId = request.params['uploadId']!;
    final session = _uploads[uploadId];
    if (session == null) {
      return _error(404, 'NOT_FOUND', 'Upload session not found or expired');
    }
    if (session.alias != alias) {
      return _error(404, 'NOT_FOUND', 'Upload session not found or expired');
    }

    final contentRange = request.headers['content-range'];
    if (contentRange == null) {
      return _error(400, 'INVALID_ARGUMENT', 'Content-Range header required');
    }

    final range = _parseContentRange(contentRange);
    if (range == null) {
      return _error(
        400,
        'INVALID_ARGUMENT',
        'Malformed Content-Range header (expected: bytes <start>-<end>/<total>)',
      );
    }
    final (start, end, total) = range;

    // Validate alignment: start must match current offset.
    if (start != session.bytesReceived) {
      return Response(
        409,
        headers: _json,
        body: jsonEncode({
          'error': {
            'code': 'OFFSET_MISMATCH',
            'message':
                'Expected offset ${session.bytesReceived}, got $start',
          },
          'offset': session.bytesReceived,
        }),
      );
    }

    // Append chunk to temp file.
    final tmp = File(session.tmpPath);
    final sink = tmp.openWrite(mode: FileMode.append);
    try {
      await sink.addStream(request.read());
      await sink.flush();
    } finally {
      await sink.close();
    }

    final chunkSize = end - start + 1;
    session.bytesReceived += chunkSize;

    return Response.ok(
      jsonEncode({'offset': session.bytesReceived}),
      headers: _json,
    );
  };
}

// ─── POST /v1/roots/<alias>/upload/<uploadId>/complete ────────────────────────

/// Finalises a resumable upload.
///
/// Request body:
/// ```json
/// { "sha256": "<hex checksum of the complete file>" }
/// ```
///
/// On success atomically renames the temp file to the target path.
///
/// Response:
/// ```json
/// { "versionToken": "<token>" }
/// ```
Handler uploadCompleteHandler(RootRegistry registry, ActivityLog log) {
  return (Request request) async {
    final alias = request.params['alias']!;
    if (registry.get(alias) == null) {
      return _error(404, 'NOT_FOUND', 'Root not found');
    }

    final role = roleOf(request);
    if (!role.canWrite()) {
      return _error(403, 'FORBIDDEN', 'Write access required');
    }

    final uploadId = request.params['uploadId']!;
    final session = _uploads[uploadId];
    if (session == null) {
      return _error(404, 'NOT_FOUND', 'Upload session not found or expired');
    }
    if (session.alias != alias) {
      return _error(404, 'NOT_FOUND', 'Upload session not found or expired');
    }

    final body = await _parseJson(request);
    if (body == null) return _error(400, 'INVALID_ARGUMENT', 'Invalid JSON');

    final expectedChecksum = body['sha256'] as String?;
    if (expectedChecksum == null) {
      return _error(400, 'INVALID_ARGUMENT', 'sha256 checksum is required');
    }

    final tmp = File(session.tmpPath);
    if (!tmp.existsSync()) {
      _uploads.remove(uploadId);
      return _error(500, 'INTERNAL_ERROR', 'Upload temp file missing');
    }

    // Verify checksum.
    final actualChecksum =
        sha256.convert(await tmp.readAsBytes()).toString();
    if (actualChecksum != expectedChecksum) {
      // Clean up temp file on checksum failure.
      await tmp.delete().catchError((_) => File(session.tmpPath));
      _uploads.remove(uploadId);
      return Response(
        422,
        headers: _json,
        body: jsonEncode({
          'error': {
            'code': 'CHECKSUM_MISMATCH',
            'message': 'File checksum does not match. Re-upload required.',
          },
        }),
      );
    }

    // Atomic rename to final destination.
    await tmp.rename(session.targetPath);
    _uploads.remove(uploadId);

    final versionToken =
        computeVersionToken(File(session.targetPath).statSync());

    log.record(
      id: _uuid.v4(),
      deviceId: '',
      deviceName: 'guest',
      rootAlias: alias,
      operation: 'upload_complete',
      path: session.targetPath,
      result: 'ok',
    );

    return Response.ok(
      jsonEncode({'versionToken': versionToken}),
      headers: _json,
    );
  };
}

// ─── GET /v1/roots/<alias>/upload/<uploadId>/offset ───────────────────────────

/// Returns the current received offset for a resumable upload.
/// Allows clients to query after a disconnection to determine where to resume.
///
/// Response:
/// ```json
/// { "offset": <bytes_received_so_far>, "totalSize": <expected_total> }
/// ```
Handler uploadOffsetHandler(RootRegistry registry) {
  return (Request request) {
    final alias = request.params['alias']!;
    if (registry.get(alias) == null) {
      return _error(404, 'NOT_FOUND', 'Root not found');
    }

    final uploadId = request.params['uploadId']!;
    final session = _uploads[uploadId];
    if (session == null || session.alias != alias) {
      return _error(404, 'NOT_FOUND', 'Upload session not found or expired');
    }

    return Response.ok(
      jsonEncode({
        'offset': session.bytesReceived,
        'totalSize': session.totalSize,
      }),
      headers: _json,
    );
  };
}

// ─── DELETE /v1/roots/<alias>/upload/<uploadId> (cancel) ─────────────────────

/// Cancels and discards a resumable upload session.
Handler uploadCancelHandler(RootRegistry registry) {
  return (Request request) async {
    final alias = request.params['alias']!;
    final uploadId = request.params['uploadId']!;
    final session = _uploads[uploadId];

    if (session == null || session.alias != alias) {
      return _error(404, 'NOT_FOUND', 'Upload session not found or expired');
    }

    final tmp = File(session.tmpPath);
    if (tmp.existsSync()) {
      await tmp.delete().catchError((_) => File(session.tmpPath));
    }
    _uploads.remove(uploadId);

    return Response.ok(
      jsonEncode({'cancelled': uploadId}),
      headers: _json,
    );
  };
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Parses `Content-Range: bytes <start>-<end>/<total>`.
/// Returns (start, end, total) or null on malformed input.
(int, int, int)? _parseContentRange(String header) {
  final match =
      RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(header.trim());
  if (match == null) return null;
  final start = int.tryParse(match.group(1)!);
  final end = int.tryParse(match.group(2)!);
  final total = int.tryParse(match.group(3)!);
  if (start == null || end == null || total == null) return null;
  if (start > end || end >= total) return null;
  return (start, end, total);
}

Response _error(int status, String code, String message) => Response(
      status,
      headers: _json,
      body: jsonEncode({
        'error': {'code': code, 'message': message},
      }),
    );

Future<Map<String, dynamic>?> _parseJson(Request request) async {
  try {
    final body = await request.readAsString();
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}
