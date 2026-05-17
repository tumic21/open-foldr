import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';
import '../roots/root_registry.dart';
import '../auth/auth_middleware.dart';
import '../activity/activity_log.dart';
import '../../core/atomic_write.dart';
import '../../core/result.dart';
import 'handlers.dart' show computeVersionToken, stripLeadingSlash;

final _uuid = const Uuid();

const _json = {'content-type': 'application/json'};

// ─── File Upload (PUT) ────────────────────────────────────────────────────────

/// `PUT /v1/roots/<alias>/file?path=<path>`
///
/// Creates or updates a file under [alias] at [path].
///
/// - For **updates** to an existing file the `If-Match` header MUST contain
///   the current version token. A mismatch returns 409 with the latest token.
/// - For **new files** `If-Match` is not required.
/// - Pass `If-Match: *` to force-overwrite an existing file without a version
///   check (owner-only operation).
/// - Writes are performed atomically (temp-file + rename).
Handler fileUploadHandler(RootRegistry registry, ActivityLog log) {
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
    final rawPath = request.url.queryParameters['path'] ?? '';
    if (rawPath.isEmpty) {
      return _error(400, 'INVALID_ARGUMENT', 'path is required');
    }

    final resolved = guard.resolve(stripLeadingSlash(rawPath));
    if (resolved.isErr) {
      return _error(400, resolved.errorCode, resolved.errorMessage);
    }

    final targetPath = resolved.unwrap;
    final file = File(targetPath);
    final exists = file.existsSync();

    if (exists) {
      final ifMatch = request.headers['if-match'];
      if (ifMatch == null) {
        return _error(
          428,
          'PRECONDITION_REQUIRED',
          'If-Match header required when updating an existing file',
        );
      }

      // `If-Match: *` means force-overwrite; only owners may do this.
      if (ifMatch != '*') {
        final current = computeVersionToken(file.statSync());
        if (ifMatch != current) {
          return Response(
            409,
            headers: _json,
            body: jsonEncode({
              'error': {
                'code': 'VERSION_CONFLICT',
                'message': 'File was modified by another client',
              },
              'versionToken': current,
            }),
          );
        }
      } else if (!role.canDelete()) {
        // Force-overwrite (* wildcard) is restricted to owner.
        return _error(403, 'FORBIDDEN', 'Force-overwrite requires owner role');
      }
    } else {
      // Ensure the parent directory exists before writing.
      final parent = Directory(file.parent.path);
      if (!parent.existsSync()) parent.createSync(recursive: true);
    }

    await atomicWrite(targetPath, request.read());

    final newToken = computeVersionToken(File(targetPath).statSync());

    log.record(
      id: _uuid.v4(),
      deviceId: deviceIdOf(request),
      deviceName: deviceNameOf(request),
      rootAlias: alias,
      operation: exists ? 'update' : 'create',
      path: rawPath,
      result: 'ok',
    );

    return Response.ok(jsonEncode({'versionToken': newToken}), headers: _json);
  };
}

// ─── File Delete (DELETE) ─────────────────────────────────────────────────────

/// `DELETE /v1/roots/<alias>/file?path=<path>`
///
/// Deletes a file or directory (recursively). Requires owner role.
Handler fileDeleteHandler(RootRegistry registry, ActivityLog log) {
  return (Request request) async {
    final alias = request.params['alias']!;
    if (registry.get(alias) == null) {
      return _error(404, 'NOT_FOUND', 'Root not found');
    }

    final role = roleOf(request);
    if (!role.canDelete()) {
      return _error(403, 'FORBIDDEN', 'Delete access requires owner role');
    }

    final guard = registry.guard(alias)!;
    final rawPath = request.url.queryParameters['path'] ?? '';
    if (rawPath.isEmpty) {
      return _error(400, 'INVALID_ARGUMENT', 'path is required');
    }

    final resolved = guard.resolve(stripLeadingSlash(rawPath));
    if (resolved.isErr) {
      return _error(400, resolved.errorCode, resolved.errorMessage);
    }

    final targetPath = resolved.unwrap;
    final file = File(targetPath);
    final dir = Directory(targetPath);

    try {
      if (file.existsSync()) {
        await file.delete();
      } else if (dir.existsSync()) {
        await dir.delete(recursive: true);
      } else {
        return _error(404, 'NOT_FOUND', 'Path not found');
      }
    } on FileSystemException catch (e) {
      return _mapDeleteFileSystemErrorResponse(e);
    }

    log.record(
      id: _uuid.v4(),
      deviceId: deviceIdOf(request),
      deviceName: deviceNameOf(request),
      rootAlias: alias,
      operation: 'delete',
      path: rawPath,
      result: 'ok',
    );

    return Response.ok(jsonEncode({'deleted': rawPath}), headers: _json);
  };
}

// ─── Batch Delete (POST) ──────────────────────────────────────────────────────

/// `POST /v1/roots/<alias>/batch/delete`
///
/// Deletes multiple paths in a single request. Returns a per-item result for
/// each path regardless of individual failures (partial success is possible).
///
/// Request body: `{ "paths": ["/foo.txt", "/bar/"] }`
///
/// Response: `{ "results": [ { "path": "/foo.txt", "status": 200, "message": "deleted" }, … ] }`
Handler batchDeleteHandler(RootRegistry registry, ActivityLog log) {
  return (Request request) async {
    final alias = request.params['alias']!;
    if (registry.get(alias) == null) {
      return _error(404, 'NOT_FOUND', 'Root not found');
    }

    final role = roleOf(request);
    if (!role.canDelete()) {
      return _error(403, 'FORBIDDEN', 'Delete access requires owner role');
    }

    final guard = registry.guard(alias)!;
    final body = await _parseJson(request);
    if (body == null) return _error(400, 'INVALID_ARGUMENT', 'Invalid JSON');

    final paths = (body['paths'] as List?)?.cast<String>();
    if (paths == null || paths.isEmpty) {
      return _error(400, 'INVALID_ARGUMENT', 'paths array is required');
    }

    final results = <Map<String, dynamic>>[];

    for (final rawPath in paths) {
      final resolved = guard.resolve(stripLeadingSlash(rawPath));
      if (resolved.isErr) {
        results.add({
          'path': rawPath,
          'status': 400,
          'message': resolved.errorMessage,
        });
        continue;
      }

      final targetPath = resolved.unwrap;
      try {
        final file = File(targetPath);
        final dir = Directory(targetPath);
        if (file.existsSync()) {
          await file.delete();
          results.add({'path': rawPath, 'status': 200, 'message': 'deleted'});
          log.record(
            id: _uuid.v4(),
            deviceId: deviceIdOf(request),
            deviceName: deviceNameOf(request),
            rootAlias: alias,
            operation: 'delete',
            path: rawPath,
            result: 'ok',
          );
        } else if (dir.existsSync()) {
          await dir.delete(recursive: true);
          results.add({'path': rawPath, 'status': 200, 'message': 'deleted'});
          log.record(
            id: _uuid.v4(),
            deviceId: deviceIdOf(request),
            deviceName: deviceNameOf(request),
            rootAlias: alias,
            operation: 'delete',
            path: rawPath,
            result: 'ok',
          );
        } else {
          results.add({'path': rawPath, 'status': 404, 'message': 'not found'});
        }
      } on FileSystemException catch (e) {
        final mapped = _mapDeleteFileSystemError(e);
        results.add({
          'path': rawPath,
          'status': mapped.$1,
          'message': mapped.$2,
        });
      } catch (e) {
        results.add({
          'path': rawPath,
          'status': 500,
          'message': 'Delete failed',
        });
      }
    }

    return Response.ok(jsonEncode({'results': results}), headers: _json);
  };
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

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

(int, String) _mapDeleteFileSystemError(FileSystemException error) {
  final errno = error.osError?.errorCode;
  if (errno == 13 || errno == 5 || errno == 1 || errno == 30) {
    return (
      403,
      'Host process does not have filesystem permission to delete this item',
    );
  }

  if (errno == 2) {
    return (404, 'Path not found');
  }

  final details = '${error.osError?.message ?? error.message}'.toLowerCase();
  if (details.contains('permission denied') ||
      details.contains('access is denied') ||
      details.contains('operation not permitted') ||
      details.contains('read-only file system')) {
    return (
      403,
      'Host process does not have filesystem permission to delete this item',
    );
  }

  return (500, 'Delete failed');
}

Response _mapDeleteFileSystemErrorResponse(FileSystemException error) {
  final mapped = _mapDeleteFileSystemError(error);
  if (mapped.$1 == 403) {
    return _error(mapped.$1, 'PERMISSION_DENIED', mapped.$2);
  }
  if (mapped.$1 == 404) {
    return _error(mapped.$1, 'NOT_FOUND', mapped.$2);
  }
  return _error(mapped.$1, 'INTERNAL', mapped.$2);
}
