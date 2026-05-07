import 'dart:convert';
import 'package:shelf/shelf.dart';
import '../pairing/token_store.dart';
import '../../models/role.dart';

const _roleKey = 'openfoldr.role';
const _deviceIdKey = 'openfoldr.deviceId';
const _deviceNameKey = 'openfoldr.deviceName';

/// Shelf middleware that enforces Bearer token authentication.
Middleware bearerAuthMiddleware(TokenStore store) {
  return (Handler inner) {
    return (Request request) async {
      // Health endpoint is public.
      if (request.url.path == 'v1/health') return inner(request);
      // Auth endpoints are public.
      if (request.url.path.startsWith('v1/auth/')) return inner(request);

      final watchToken = request.url.queryParameters['token'];
      final isWatchRequest =
          request.method == 'GET' && request.url.path.endsWith('/watch');
      if (isWatchRequest && watchToken != null && watchToken.isNotEmpty) {
        final auth = store.validateWithDevice(watchToken);
        if (auth == null) {
          return _unauthorized('Token invalid or expired');
        }

        final updated = request.change(
          context: {
            ...request.context,
            _roleKey: auth.role,
            _deviceIdKey: auth.deviceId,
            _deviceNameKey: auth.deviceName,
          },
        );
        return inner(updated);
      }

      final header = request.headers['authorization'] ?? '';
      if (!header.startsWith('Bearer ')) {
        return _unauthorized('Missing or invalid Authorization header');
      }

      final token = header.substring(7);
      final auth = store.validateWithDevice(token);
      if (auth == null) {
        return _unauthorized('Token invalid or expired');
      }

      // Pass role and device context into request locals.
      final updated = request.change(
        context: {
          ...request.context,
          _roleKey: auth.role,
          _deviceIdKey: auth.deviceId,
          _deviceNameKey: auth.deviceName,
        },
      );

      return inner(updated);
    };
  };
}

/// Extracts the [Role] from a [Request] context set by [bearerAuthMiddleware].
Role roleOf(Request request) =>
    request.context[_roleKey] as Role? ?? Role.viewer;

String deviceIdOf(Request request) =>
    request.context[_deviceIdKey] as String? ?? '';

String deviceNameOf(Request request) =>
    request.context[_deviceNameKey] as String? ?? 'unknown';

Response _unauthorized(String message) => Response(
  401,
  headers: {'content-type': 'application/json'},
  body: jsonEncode({
    'error': {'code': 'UNAUTHORIZED', 'message': message},
  }),
);
