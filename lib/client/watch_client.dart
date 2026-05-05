import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/backoff.dart';

/// A filesystem-change event emitted by the server's watch endpoint.
class FileEvent {
  /// One of: `created`, `modified`, `deleted`, `moved`.
  final String type;

  /// Server-relative path of the affected file/directory (e.g. `/docs/file.txt`).
  final String path;

  /// For `moved` events: the new path. Otherwise `null`.
  final String? movedTo;

  const FileEvent({
    required this.type,
    required this.path,
    this.movedTo,
  });

  factory FileEvent.fromJson(Map<String, dynamic> json) => FileEvent(
        type: json['type'] as String,
        path: json['path'] as String,
        movedTo: json['movedTo'] as String?,
      );

  @override
  String toString() =>
      'FileEvent(type: $type, path: $path, movedTo: $movedTo)';
}

/// Connects to the server's WebSocket watch endpoint and exposes a
/// [Stream<FileEvent>].
///
/// Reconnects automatically with exponential backoff on unexpected disconnects.
/// Call [dispose] to permanently close the connection.
class WatchClient {
  final String baseUrl;
  final String sessionToken;
  final String alias;
  final String watchPath;

  /// Internal stream controller that consumers listen on.
  final _controller = StreamController<FileEvent>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  bool _disposed = false;
  int _attempt = 0;
  Timer? _reconnectTimer;

  /// Constructor — does **not** connect automatically.
  /// Call [connect] to start streaming.
  WatchClient({
    required this.baseUrl,
    required this.sessionToken,
    required this.alias,
    this.watchPath = '/',
  });

  /// The stream of [FileEvent]s from the server.
  Stream<FileEvent> get events => _controller.stream;

  /// Builds the WebSocket [Uri] for this client's current parameters.
  ///
  /// Converts `http(s)://` to `ws(s)://` and appends query parameters.
  Uri buildWsUri() {
    final wsBase = baseUrl
        .replaceFirst(RegExp(r'^http://'), 'ws://')
        .replaceFirst(RegExp(r'^https://'), 'wss://');
    return Uri.parse(
        '$wsBase/roots/$alias/watch?path=${Uri.encodeComponent(watchPath)}&token=${Uri.encodeComponent(sessionToken)}');
  }

  /// Establishes (or re-establishes) the WebSocket connection.
  void connect() {
    if (_disposed) return;
    _cancelCurrentConnection();

    final uri = buildWsUri();

    try {
      _channel = WebSocketChannel.connect(
        uri,
        protocols: const [],
      );

      // Authenticate via sub-protocol is not used; instead pass the token as
      // a query param isn't ideal.  shelf_web_socket supports header-based
      // auth on the upgrade request, but WebSocketChannel.connect on Flutter
      // doesn't allow custom headers on all platforms.  We rely on the outer
      // middleware having already verified the token via a prior HTTP call,
      // and use a query-param token approach for the WS upgrade.
      //
      // Reconnect after opening: send a lightweight ping to authenticate.
      // The server will close with 4401 if token is invalid.

      _sub = _channel!.stream.listen(
        (data) {
          _attempt = 0; // reset backoff on successful message
          if (data is String) {
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              _controller.add(FileEvent.fromJson(json));
            } catch (_) {
              // Ignore malformed events.
            }
          }
        },
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _cancelCurrentConnection() {
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    _cancelCurrentConnection();
    final delay = backoffDelay(attempt: _attempt++, rng: Random());
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, connect);
  }

  /// Permanently closes the connection and the event stream.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _reconnectTimer?.cancel();
    _cancelCurrentConnection();
    _controller.close();
  }
}
