import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/result.dart';
import '../pairing/token_store.dart';
import '../roots/root_registry.dart';

/// `GET /v1/roots/<alias>/watch`
///
/// Upgrades the connection to a WebSocket and streams [FileEvent] JSON
/// messages to the client whenever the watched directory changes.
///
/// Role requirement: viewer and above (all authenticated clients).
///
/// Event shape:
/// ```json
/// { "type": "created|modified|deleted|moved",
///   "path": "relative/path",
///   "movedTo": "relative/new-path"  // only for "moved" events
/// }
/// ```
///
/// The handler watches the *current directory* (query param `path`, default `/`)
/// non-recursively and debounces rapid bursts with a 150 ms window.
Handler watchHandler(RootRegistry registry) {
  return webSocketHandler((WebSocketChannel ws, String? protocol) async {
    // webSocketHandler provides no Request context so we cannot re-check auth
    // here — auth is enforced by the outer bearerAuthMiddleware before the
    // upgrade.  We do, however, need the alias from the URL.  shelf_web_socket
    // does not pass the Request directly, so alias is embedded via a closure
    // in the per-route wrapper below.
  });
}

/// Returns a [Handler] that, for GET requests, upgrades to WebSocket and
/// streams filesystem events for [alias]/[watchPath].
///
/// Usage: register with the shelf router as
/// `..get('/v1/roots/<alias>/watch', watchRouteHandler(registry, tokens))`
///
/// Authentication: uses the standard `Authorization: Bearer <token>` header
/// sent in the WebSocket upgrade request, validated by bearerAuthMiddleware.
Handler watchRouteHandler(RootRegistry registry, TokenStore tokens) {
  return (Request request) async {
    final alias = request.params['alias']!;
    final root = registry.get(alias);
    if (root == null) {
      return Response.notFound(
        jsonEncode({'error': {'code': 'NOT_FOUND', 'message': 'Root not found'}}),
        headers: {'content-type': 'application/json'},
      );
    }

    // Authentication is enforced by the bearerAuthMiddleware before this
    // handler is called. The middleware validates the Authorization: Bearer
    // header (sent in the WebSocket upgrade request) and sets 'role' in the
    // request context if the token is valid.
    final authenticated = request.context.containsKey('role');

    if (!authenticated) {
      return Response(401,
          body: jsonEncode(
              {'error': {'code': 'UNAUTHORIZED', 'message': 'Authentication required'}}),
          headers: {'content-type': 'application/json'});
    }

    // Determine which sub-path to watch (default: root of alias).
    final rawPath = request.url.queryParameters['path'] ?? '/';
    final guard = registry.guard(alias)!;
    final resolvedResult = guard.resolve(
        rawPath.startsWith('/') ? rawPath.substring(1) : rawPath);
    if (resolvedResult.isErr) {
      return Response(400,
          body: jsonEncode({
            'error': {
              'code': resolvedResult.errorCode,
              'message': resolvedResult.errorMessage,
            }
          }),
          headers: {'content-type': 'application/json'});
    }

    final watchDir = Directory(resolvedResult.unwrap);
    if (!watchDir.existsSync()) {
      // Fallback to root of alias if the specific path doesn't exist yet.
      final rootDir = Directory(root.localPath);
      if (!rootDir.existsSync()) {
        return Response.notFound(
          jsonEncode({'error': {'code': 'NOT_FOUND', 'message': 'Directory not found'}}),
          headers: {'content-type': 'application/json'},
        );
      }
    }

    final effectiveDir = watchDir.existsSync() ? watchDir : Directory(root.localPath);

    // Upgrade to WebSocket.
    final wsHandler = webSocketHandler(
      (WebSocketChannel channel, String? proto) {
        _watchDirectory(effectiveDir, root.localPath, channel);
      },
    );

    return wsHandler(request);
  };
}

/// Attaches a [Directory.watch] listener to [dir], translates events to
/// [FileEvent] JSON, debounces bursts, and sends them over [channel].
void _watchDirectory(
  Directory dir,
  String rootLocalPath,
  WebSocketChannel channel,
) {
  StreamSubscription<FileSystemEvent>? fsSub;
  Timer? debounceTimer;
  final pending = <Map<String, String?>>[];
  var closed = false;

  void flush() {
    if (pending.isEmpty || closed) return;
    final batch = List<Map<String, String?>>.from(pending);
    pending.clear();
    for (final event in batch) {
      try {
        channel.sink.add(jsonEncode(event));
      } catch (_) {
        // Channel may have closed between flush scheduling and execution.
      }
    }
  }

  void enqueue(Map<String, String?> event) {
    if (closed) return;
    pending.add(event);
    debounceTimer?.cancel();
    debounceTimer = Timer(const Duration(milliseconds: 150), flush);
  }

  String relPath(String absolutePath) {
    final rel = absolutePath.startsWith(rootLocalPath)
        ? absolutePath.substring(rootLocalPath.length)
        : absolutePath;
    return rel.startsWith('/') ? rel : '/$rel';
  }

  try {
    fsSub = dir.watch(recursive: false).listen(
      (event) {
        final type = switch (event.type) {
          FileSystemEvent.create => 'created',
          FileSystemEvent.modify => 'modified',
          FileSystemEvent.delete => 'deleted',
          FileSystemEvent.move => 'moved',
          _ => 'modified',
        };

        String? movedTo;
        if (event is FileSystemMoveEvent) {
          movedTo = event.destination != null ? relPath(event.destination!) : null;
        }

        enqueue({
          'type': type,
          'path': relPath(event.path),
          if (movedTo != null) 'movedTo': movedTo,
        });
      },
      onError: (_) {
        // Watcher error (e.g. directory deleted) — close cleanly.
        closed = true;
        fsSub?.cancel();
        channel.sink.close();
      },
      onDone: () {
        closed = true;
        channel.sink.close();
      },
    );
  } catch (_) {
    // Directory.watch not supported on this platform — close immediately.
    channel.sink.close();
    return;
  }

  // Cancel fs watch when client disconnects.
  channel.stream.drain<void>().then((_) {
    closed = true;
    debounceTimer?.cancel();
    fsSub?.cancel();
  }).catchError((_) {
    closed = true;
    debounceTimer?.cancel();
    fsSub?.cancel();
  });
}
