import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:uuid/uuid.dart';
import '../roots/root_registry.dart';
import '../auth/auth_middleware.dart';
import '../activity/activity_log.dart';
import '../../core/atomic_write.dart';
import '../../core/result.dart';
import 'handlers.dart' show stripLeadingSlash;

final _uuid = const Uuid();

const _json = {'content-type': 'application/json'};

// ─── mkdir ────────────────────────────────────────────────────────────────────

/// `POST /v1/roots/<alias>/mkdir`
///
/// Creates a new directory at [path] within [alias].
///
/// Request body: `{ "path": "docs/new-folder" }`
///
/// Responses:
/// - 201 Created
/// - 400 Invalid path / traversal
/// - 403 Insufficient role (editor required)
/// - 404 Root not found
/// - 409 Directory already exists
Handler mkdirHandler(RootRegistry registry, ActivityLog log) {
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
    if (rawPath == null || rawPath.trim().isEmpty) {
      return _error(400, 'INVALID_ARGUMENT', 'path is required');
    }

    final resolved = guard.resolve(stripLeadingSlash(rawPath));
    if (resolved.isErr) {
      return _error(400, resolved.errorCode, resolved.errorMessage);
    }

    final dir = Directory(resolved.unwrap);
    if (dir.existsSync()) {
      return _error(409, 'ALREADY_EXISTS', 'Directory already exists');
    }

    dir.createSync(recursive: true);

    log.record(
      id: _uuid.v4(),
      deviceId: deviceIdOf(request),
      deviceName: deviceNameOf(request),
      rootAlias: alias,
      operation: 'mkdir',
      path: rawPath,
      result: 'ok',
    );

    return Response(
      201,
      headers: _json,
      body: jsonEncode({'created': rawPath}),
    );
  };
}

// ─── rename ───────────────────────────────────────────────────────────────────

/// `POST /v1/roots/<alias>/rename`
///
/// Renames (or moves) a single file or directory within the same root.
///
/// Request body: `{ "from": "docs/old.txt", "to": "docs/new.txt" }`
///
/// Responses:
/// - 200 OK
/// - 400 Invalid paths / traversal
/// - 403 Insufficient role (editor required)
/// - 404 Root or source not found
/// - 409 Target already exists
Handler renameHandler(RootRegistry registry, ActivityLog log) {
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

    final rawFrom = body['from'] as String?;
    final rawTo = body['to'] as String?;
    if (rawFrom == null || rawTo == null) {
      return _error(400, 'INVALID_ARGUMENT', 'from and to are required');
    }

    final resolvedFrom = guard.resolve(stripLeadingSlash(rawFrom));
    if (resolvedFrom.isErr) {
      return _error(400, resolvedFrom.errorCode, resolvedFrom.errorMessage);
    }

    final resolvedTo = guard.resolve(stripLeadingSlash(rawTo));
    if (resolvedTo.isErr) {
      return _error(400, resolvedTo.errorCode, resolvedTo.errorMessage);
    }

    final fromPath = resolvedFrom.unwrap;
    final toPath = resolvedTo.unwrap;

    final sourceFile = File(fromPath);
    final sourceDir = Directory(fromPath);
    final bool sourceIsFile = sourceFile.existsSync();
    final bool sourceIsDir = sourceDir.existsSync();

    if (!sourceIsFile && !sourceIsDir) {
      return _error(404, 'NOT_FOUND', 'Source path not found');
    }

    if (File(toPath).existsSync() || Directory(toPath).existsSync()) {
      return _error(409, 'ALREADY_EXISTS', 'Target path already exists');
    }

    // Ensure parent directory of destination exists.
    final destParent = Directory(p.dirname(toPath));
    if (!destParent.existsSync()) {
      destParent.createSync(recursive: true);
    }

    // `File.rename` / `Directory.rename` are atomic on POSIX when on the same
    // filesystem. Cross-device moves will throw a FileSystemException and we
    // fall back to copy + delete.
    try {
      if (sourceIsFile) {
        await sourceFile.rename(toPath);
      } else {
        await sourceDir.rename(toPath);
      }
    } on FileSystemException {
      // Cross-device fallback.
      if (sourceIsFile) {
        final destFile = File(toPath);
        await sourceFile.copy(toPath);
        await sourceFile.delete();
        // Verify the destination was actually written before deleting source.
        if (!destFile.existsSync()) {
          return _error(500, 'INTERNAL', 'Cross-device rename failed');
        }
      } else {
        await _copyDirectoryRecursive(sourceDir, Directory(toPath));
        await sourceDir.delete(recursive: true);
      }
    }

    log.record(
      id: _uuid.v4(),
      deviceId: deviceIdOf(request),
      deviceName: deviceNameOf(request),
      rootAlias: alias,
      operation: 'rename',
      path: rawFrom,
      result: 'ok',
    );

    return Response.ok(
      jsonEncode({'from': rawFrom, 'to': rawTo}),
      headers: _json,
    );
  };
}

// ─── copy ─────────────────────────────────────────────────────────────────────

/// `POST /v1/roots/<alias>/copy`
///
/// Copies a single file or directory within the same root.
///
/// Request body: `{ "from": "docs/file.txt", "to": "archive/file.txt" }`
///
/// Responses:
/// - 201 Created
/// - 400 Invalid paths / traversal
/// - 403 Insufficient role (editor required)
/// - 404 Root or source not found
/// - 409 Target already exists
Handler copyHandler(RootRegistry registry, ActivityLog log) {
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

    final rawFrom = body['from'] as String?;
    final rawTo = body['to'] as String?;
    if (rawFrom == null || rawTo == null) {
      return _error(400, 'INVALID_ARGUMENT', 'from and to are required');
    }

    final resolvedFrom = guard.resolve(stripLeadingSlash(rawFrom));
    if (resolvedFrom.isErr) {
      return _error(400, resolvedFrom.errorCode, resolvedFrom.errorMessage);
    }

    final resolvedTo = guard.resolve(stripLeadingSlash(rawTo));
    if (resolvedTo.isErr) {
      return _error(400, resolvedTo.errorCode, resolvedTo.errorMessage);
    }

    final fromPath = resolvedFrom.unwrap;
    final toPath = resolvedTo.unwrap;

    final sourceFile = File(fromPath);
    final sourceDir = Directory(fromPath);
    final bool sourceIsFile = sourceFile.existsSync();
    final bool sourceIsDir = sourceDir.existsSync();

    if (!sourceIsFile && !sourceIsDir) {
      return _error(404, 'NOT_FOUND', 'Source path not found');
    }

    if (File(toPath).existsSync() || Directory(toPath).existsSync()) {
      return _error(409, 'ALREADY_EXISTS', 'Target path already exists');
    }

    // Ensure parent directory of destination exists.
    final destParent = Directory(p.dirname(toPath));
    if (!destParent.existsSync()) {
      destParent.createSync(recursive: true);
    }

    if (sourceIsFile) {
      // Use atomicWrite to be consistent with the rest of the codebase.
      await atomicWrite(toPath, sourceFile.openRead());
    } else {
      await _copyDirectoryRecursive(sourceDir, Directory(toPath));
    }

    log.record(
      id: _uuid.v4(),
      deviceId: deviceIdOf(request),
      deviceName: deviceNameOf(request),
      rootAlias: alias,
      operation: 'copy',
      path: rawFrom,
      result: 'ok',
    );

    return Response(
      201,
      headers: _json,
      body: jsonEncode({'from': rawFrom, 'to': rawTo}),
    );
  };
}

// ─── batch/move ───────────────────────────────────────────────────────────────

/// `POST /v1/roots/<alias>/batch/move`
///
/// Moves multiple items into [destination] within the same root.
///
/// Request body:
/// ```json
/// { "items": ["a/x.txt", "a/y.txt"], "destination": "b/" }
/// ```
///
/// Response (200 on full success, 207 on partial failure):
/// ```json
/// { "results": [ { "item": "a/x.txt", "status": 200, "message": "moved" }, … ] }
/// ```
Handler batchMoveHandler(RootRegistry registry, ActivityLog log) {
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

    final items = (body['items'] as List?)?.cast<String>();
    final rawDest = body['destination'] as String?;
    if (items == null || items.isEmpty || rawDest == null) {
      return _error(
        400,
        'INVALID_ARGUMENT',
        'items array and destination are required',
      );
    }

    final resolvedDest = guard.resolve(stripLeadingSlash(rawDest));
    if (resolvedDest.isErr) {
      return _error(400, resolvedDest.errorCode, resolvedDest.errorMessage);
    }

    final destDirPath = resolvedDest.unwrap;
    final destDir = Directory(destDirPath);
    if (!destDir.existsSync()) {
      destDir.createSync(recursive: true);
    }

    final results = <Map<String, dynamic>>[];
    bool hasFailure = false;

    for (final rawItem in items) {
      final resolvedItem = guard.resolve(stripLeadingSlash(rawItem));
      if (resolvedItem.isErr) {
        results.add({
          'item': rawItem,
          'status': 400,
          'message': resolvedItem.errorMessage,
        });
        hasFailure = true;
        continue;
      }

      final itemPath = resolvedItem.unwrap;
      final itemName = p.basename(itemPath);
      final toPath = p.join(destDirPath, itemName);

      try {
        final sourceFile = File(itemPath);
        final sourceDir = Directory(itemPath);
        final bool sourceIsFile = sourceFile.existsSync();
        final bool sourceIsDir = sourceDir.existsSync();

        if (!sourceIsFile && !sourceIsDir) {
          results.add({'item': rawItem, 'status': 404, 'message': 'not found'});
          hasFailure = true;
          continue;
        }

        if (File(toPath).existsSync() || Directory(toPath).existsSync()) {
          results.add({
            'item': rawItem,
            'status': 409,
            'message': 'target already exists',
          });
          hasFailure = true;
          continue;
        }

        try {
          if (sourceIsFile) {
            await sourceFile.rename(toPath);
          } else {
            await sourceDir.rename(toPath);
          }
        } on FileSystemException {
          // Cross-device fallback.
          if (sourceIsFile) {
            await sourceFile.copy(toPath);
            await sourceFile.delete();
          } else {
            await _copyDirectoryRecursive(sourceDir, Directory(toPath));
            await sourceDir.delete(recursive: true);
          }
        }

        results.add({'item': rawItem, 'status': 200, 'message': 'moved'});
        log.record(
          id: _uuid.v4(),
          deviceId: deviceIdOf(request),
          deviceName: deviceNameOf(request),
          rootAlias: alias,
          operation: 'move',
          path: rawItem,
          result: 'ok',
        );
      } catch (e) {
        results.add({
          'item': rawItem,
          'status': 500,
          'message': 'Internal error: ${e.toString()}',
        });
        hasFailure = true;
      }
    }

    final statusCode = hasFailure ? 207 : 200;
    return Response(
      statusCode,
      headers: _json,
      body: jsonEncode({'results': results}),
    );
  };
}

// ─── batch/copy ───────────────────────────────────────────────────────────────

/// `POST /v1/roots/<alias>/batch/copy`
///
/// Copies multiple items into [destination] within the same root.
///
/// Request / response shape is identical to `batch/move`.
Handler batchCopyHandler(RootRegistry registry, ActivityLog log) {
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

    final items = (body['items'] as List?)?.cast<String>();
    final rawDest = body['destination'] as String?;
    if (items == null || items.isEmpty || rawDest == null) {
      return _error(
        400,
        'INVALID_ARGUMENT',
        'items array and destination are required',
      );
    }

    final resolvedDest = guard.resolve(stripLeadingSlash(rawDest));
    if (resolvedDest.isErr) {
      return _error(400, resolvedDest.errorCode, resolvedDest.errorMessage);
    }

    final destDirPath = resolvedDest.unwrap;
    final destDir = Directory(destDirPath);
    if (!destDir.existsSync()) {
      destDir.createSync(recursive: true);
    }

    final results = <Map<String, dynamic>>[];
    bool hasFailure = false;

    for (final rawItem in items) {
      final resolvedItem = guard.resolve(stripLeadingSlash(rawItem));
      if (resolvedItem.isErr) {
        results.add({
          'item': rawItem,
          'status': 400,
          'message': resolvedItem.errorMessage,
        });
        hasFailure = true;
        continue;
      }

      final itemPath = resolvedItem.unwrap;
      final itemName = p.basename(itemPath);
      final toPath = p.join(destDirPath, itemName);

      try {
        final sourceFile = File(itemPath);
        final sourceDir = Directory(itemPath);
        final bool sourceIsFile = sourceFile.existsSync();
        final bool sourceIsDir = sourceDir.existsSync();

        if (!sourceIsFile && !sourceIsDir) {
          results.add({'item': rawItem, 'status': 404, 'message': 'not found'});
          hasFailure = true;
          continue;
        }

        if (File(toPath).existsSync() || Directory(toPath).existsSync()) {
          results.add({
            'item': rawItem,
            'status': 409,
            'message': 'target already exists',
          });
          hasFailure = true;
          continue;
        }

        if (sourceIsFile) {
          await atomicWrite(toPath, sourceFile.openRead());
        } else {
          await _copyDirectoryRecursive(sourceDir, Directory(toPath));
        }

        results.add({'item': rawItem, 'status': 200, 'message': 'copied'});
        log.record(
          id: _uuid.v4(),
          deviceId: deviceIdOf(request),
          deviceName: deviceNameOf(request),
          rootAlias: alias,
          operation: 'copy',
          path: rawItem,
          result: 'ok',
        );
      } catch (e) {
        results.add({
          'item': rawItem,
          'status': 500,
          'message': 'Internal error: ${e.toString()}',
        });
        hasFailure = true;
      }
    }

    final statusCode = hasFailure ? 207 : 200;
    return Response(
      statusCode,
      headers: _json,
      body: jsonEncode({'results': results}),
    );
  };
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

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

/// Recursively copies [source] directory into [destination].
/// [destination] must not already exist.
Future<void> _copyDirectoryRecursive(
  Directory source,
  Directory destination,
) async {
  destination.createSync(recursive: true);
  for (final entity in source.listSync()) {
    final name = p.basename(entity.path);
    final destPath = p.join(destination.path, name);
    if (entity is File) {
      await atomicWrite(destPath, entity.openRead());
    } else if (entity is Directory) {
      await _copyDirectoryRecursive(entity, Directory(destPath));
    }
    // Symlinks are intentionally skipped to prevent sandbox escape.
  }
}
