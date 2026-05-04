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
      ..post('/v1/roots/<alias>/batch/delete', batchDeleteHandler(roots, log));

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
