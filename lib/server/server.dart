import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'pairing/pairing_manager.dart';
import 'pairing/token_store.dart';
import 'auth/auth_middleware.dart';
import 'roots/root_registry.dart';
import 'activity/activity_log.dart';
import 'handlers/handlers.dart';
import 'handlers/write_handlers.dart';
import 'handlers/resumable_handlers.dart';
import 'handlers/fs_handlers.dart';
import 'handlers/watch_handler.dart';
import '../core/constants.dart';

/// The embedded HTTP server that runs on the host device.
class OpenFoldrServer {
  final int port;
  final PairingManager pairing;
  final TokenStore tokens;
  final RootRegistry roots;
  final ActivityLog log;

  HttpServer? _server;

  OpenFoldrServer({
    this.port = AppConstants.defaultPort,
    PairingManager? pairing,
    TokenStore? tokens,
    RootRegistry? roots,
    ActivityLog? log,
  })  : pairing = pairing ?? PairingManager(),
        tokens = tokens ?? TokenStore(),
        roots = roots ?? RootRegistry(),
        log = log ?? ActivityLog();

  bool get isRunning => _server != null;

  Future<void> start() async {
    if (_server != null) return;

    final router = Router()
      ..get('/v1/health', healthHandler())
      ..post('/v1/auth/pair/request', pairRequestHandler(pairing))
      ..post('/v1/auth/pair/complete', pairCompleteHandler(tokens))
      ..post('/v1/auth/token/refresh', tokenRefreshHandler(tokens))
      ..get('/v1/roots', rootsListHandler(roots))
      ..get('/v1/roots/<alias>/entries', entriesHandler(roots, log))
      ..get('/v1/roots/<alias>/file', fileDownloadHandler(roots, log))
      ..get('/v1/roots/<alias>/metadata', fileMetadataHandler(roots))
      // Phase 2: write, delete, batch
      ..put('/v1/roots/<alias>/file', fileUploadHandler(roots, log))
      ..delete('/v1/roots/<alias>/file', fileDeleteHandler(roots, log))
      ..post('/v1/roots/<alias>/batch/delete', batchDeleteHandler(roots, log))
      // Phase 3: resumable upload protocol
      ..post('/v1/roots/<alias>/upload/init', uploadInitHandler(roots))
      ..patch('/v1/roots/<alias>/upload/<uploadId>', uploadChunkHandler(roots))
      ..post(
        '/v1/roots/<alias>/upload/<uploadId>/complete',
        uploadCompleteHandler(roots, log),
      )
      ..get(
        '/v1/roots/<alias>/upload/<uploadId>/offset',
        uploadOffsetHandler(roots),
      )
      ..delete(
        '/v1/roots/<alias>/upload/<uploadId>',
        uploadCancelHandler(roots),
      )
      // Phase 4: filesystem operations (mkdir, rename, copy, batch move/copy)
      ..post('/v1/roots/<alias>/mkdir', mkdirHandler(roots, log))
      ..post('/v1/roots/<alias>/rename', renameHandler(roots, log))
      ..post('/v1/roots/<alias>/copy', copyHandler(roots, log))
      ..post('/v1/roots/<alias>/batch/move', batchMoveHandler(roots, log))
      ..post('/v1/roots/<alias>/batch/copy', batchCopyHandler(roots, log))
      // Phase 9: real-time directory watch (WebSocket)
      ..get('/v1/roots/<alias>/watch', watchRouteHandler(roots, tokens));

    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(bearerAuthMiddleware(tokens))
        .addHandler(router.call);

    _server = await shelf_io.serve(
      handler,
      InternetAddress.anyIPv4,
      port,
    );
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }
}
