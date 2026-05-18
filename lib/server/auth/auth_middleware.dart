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

      // Accept token from Authorization header or, as a fallback for WebSocket
      // upgrades (which cannot set custom headers), from the ?token= query
      // parameter.
      final header = request.headers['authorization'] ?? '';
      final String token;
      if (header.startsWith('Bearer ')) {
        token = header.substring(7);
      } else {
        // Depending on adapter/proxy behavior, query params may be present on
        // either request.url (relative) or requestedUri (absolute).
        final queryToken =
            request.url.queryParameters['token'] ??
            request.requestedUri.queryParameters['token'];
        if (queryToken == null || queryToken.isEmpty) {
          return _unauthorized('Missing or invalid Authorization header');
        }
        token = queryToken;
      }
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
