/// Unit tests for [FileClient] (Phase 2).
///
/// Uses [http.MockClient] from `package:http/testing.dart` to intercept HTTP
/// calls without starting a real server.  Each test exercises one public
/// method and asserts the correct [Result] variant and parsed data.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:open_foldr/client/file_client.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

const _base = 'http://localhost:7432/v1';
const _token = 'test-session-token';

/// Builds a [FileClient] backed by [mockHandler].
FileClient _client(Future<http.Response> Function(http.Request) mockHandler) =>
    FileClient(
      baseUrl: _base,
      sessionToken: _token,
      httpClient: MockClient(mockHandler),
    );

http.Response _json(int status, Map<String, dynamic> body) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

http.Response _error(String code, String message, [int status = 400]) =>
    _json(status, {
      'error': {'code': code, 'message': message},
    });

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('FileClient.getSessionRole', () {
    test('returns current session role on 200', () async {
      final c = _client((_) async => _json(200, {'role': 'owner'}));
      final result = await c.getSessionRole();
      expect(result.isOk, isTrue);
      expect(result.unwrap, 'owner');
    });

    test('returns Err on non-200', () async {
      final c = _client((_) async => _error('FORBIDDEN', 'Denied', 403));
      final result = await c.getSessionRole();
      expect(result.isErr, isTrue);
      expect(result.errorCode, 'FORBIDDEN');
    });
  });

  // ─── listRoots ─────────────────────────────────────────────────────────

  group('FileClient.listRoots', () {
    test('returns list on 200', () async {
      final c = _client((_) async => _json(200, {
            'roots': [
              {'alias': 'docs', 'minimumRole': 'viewer'},
            ],
          }));
      final result = await c.listRoots();
      expect(result.isOk, isTrue);
      expect(result.unwrap.length, 1);
      expect(result.unwrap.first['alias'], 'docs');
    });

    test('returns Err on non-200', () async {
      final c = _client((_) async => _error('NOT_FOUND', 'No roots', 404));
      final result = await c.listRoots();
      expect(result.isErr, isTrue);
      expect(result.errorCode, 'NOT_FOUND');
    });
  });

  // ─── listEntries ───────────────────────────────────────────────────────

  group('FileClient.listEntries', () {
    final now = DateTime.now().toUtc().toIso8601String();

    test('parses entries correctly on 200', () async {
      final c = _client((_) async => _json(200, {
            'entries': [
              {
                'name': 'readme.txt',
                'path': '/readme.txt',
                'kind': 'file',
                'size': 42,
                'modifiedAt': now,
              },
              {
                'name': 'photos',
                'path': '/photos',
                'kind': 'directory',
                'size': 0,
                'modifiedAt': now,
              },
            ],
          }));

      final result = await c.listEntries('docs', '/');
      expect(result.isOk, isTrue);
      final entries = result.unwrap;
      expect(entries.length, 2);
      expect(entries[0].name, 'readme.txt');
      expect(entries[0].isFile, isTrue);
      expect(entries[1].name, 'photos');
      expect(entries[1].isDirectory, isTrue);
    });

    test('sends correct path query parameter', () async {
      late Uri capturedUri;
      final c = _client((req) async {
        capturedUri = req.url;
        return _json(200, {'entries': []});
      });
      await c.listEntries('docs', '/sub/path');
      expect(capturedUri.queryParameters['path'], '/sub/path');
    });

    test('returns Err on 403', () async {
      final c =
          _client((_) async => _error('FORBIDDEN', 'Access denied', 403));
      final result = await c.listEntries('docs', '/');
      expect(result.isErr, isTrue);
      expect(result.errorCode, 'FORBIDDEN');
    });
  });

  // ─── downloadFile ──────────────────────────────────────────────────────

  group('FileClient.downloadFile', () {
    test('returns bytes on 200', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final c = _client((_) async =>
          http.Response.bytes(bytes, 200));
      final result = await c.downloadFile('docs', '/file.bin');
      expect(result.isOk, isTrue);
      expect(result.unwrap, bytes);
    });

    test('returns Err on 404', () async {
      final c = _client((_) async => _error('NOT_FOUND', 'File not found', 404));
      final result = await c.downloadFile('docs', '/missing.txt');
      expect(result.isErr, isTrue);
      expect(result.errorCode, 'NOT_FOUND');
    });
  });

  // ─── getMetadata ───────────────────────────────────────────────────────

  group('FileClient.getMetadata', () {
    test('parses metadata on 200', () async {
      final now = DateTime.now().toUtc();
      final c = _client((_) async => _json(200, {
            'path': '/readme.txt',
            'size': 100,
            'modifiedAt': now.toIso8601String(),
            'versionToken': 'abc123',
          }));
      final result = await c.getMetadata('docs', '/readme.txt');
      expect(result.isOk, isTrue);
      expect(result.unwrap.versionToken, 'abc123');
      expect(result.unwrap.size, 100);
    });
  });

  // ─── uploadFile ────────────────────────────────────────────────────────

  group('FileClient.uploadFile', () {
    test('returns versionToken on 200', () async {
      final c =
          _client((_) async => _json(200, {'versionToken': 'tok999'}));
      final result = await c.uploadFile(
          'docs', '/new.txt', Uint8List.fromList([65, 66, 67]));
      expect(result.isOk, isTrue);
      expect(result.unwrap, 'tok999');
    });

    test('sends If-Match header when ifMatch is provided', () async {
      String? ifMatchHeader;
      final c = _client((req) async {
        ifMatchHeader = req.headers['if-match'];
        return _json(200, {'versionToken': 't1'});
      });
      await c.uploadFile('docs', '/f.txt', Uint8List(0), ifMatch: 'v1');
      expect(ifMatchHeader, 'v1');
    });

    test('returns VERSION_CONFLICT on 412', () async {
      final c = _client((_) async =>
          _error('VERSION_CONFLICT', 'Conflict', 412));
      final result =
          await c.uploadFile('docs', '/f.txt', Uint8List(0), ifMatch: 'old');
      expect(result.isErr, isTrue);
      expect(result.errorCode, 'VERSION_CONFLICT');
    });
  });

  // ─── deleteItem ────────────────────────────────────────────────────────

  group('FileClient.deleteItem', () {
    test('returns Ok on 200', () async {
      final c = _client((_) async => _json(200, {}));
      final result = await c.deleteItem('docs', '/old.txt');
      expect(result.isOk, isTrue);
    });

    test('returns Err on 403', () async {
      final c =
          _client((_) async => _error('FORBIDDEN', 'Cannot delete', 403));
      final result = await c.deleteItem('docs', '/protected.txt');
      expect(result.isErr, isTrue);
    });
  });

  // ─── mkdir ─────────────────────────────────────────────────────────────

  group('FileClient.mkdir', () {
    test('returns Ok on 201', () async {
      final c = _client((_) async =>
          http.Response(jsonEncode({'created': '/newdir'}), 201,
              headers: {'content-type': 'application/json'}));
      final result = await c.mkdir('docs', '/newdir');
      expect(result.isOk, isTrue);
    });

    test('sends path in JSON body', () async {
      String? bodyPath;
      final c = _client((req) async {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        bodyPath = body['path'] as String?;
        return http.Response('{"created":"/mydir"}', 201);
      });
      await c.mkdir('docs', '/mydir');
      expect(bodyPath, '/mydir');
    });

    test('returns ALREADY_EXISTS on 409', () async {
      final c =
          _client((_) async => _error('ALREADY_EXISTS', 'Exists', 409));
      final result = await c.mkdir('docs', '/existing');
      expect(result.isErr, isTrue);
      expect(result.errorCode, 'ALREADY_EXISTS');
    });
  });

  // ─── rename ────────────────────────────────────────────────────────────

  group('FileClient.rename', () {
    test('returns Ok on 200', () async {
      final c = _client((_) async =>
          _json(200, {'from': '/a.txt', 'to': '/b.txt'}));
      final result = await c.rename('docs', '/a.txt', '/b.txt');
      expect(result.isOk, isTrue);
    });

    test('sends from and to in body', () async {
      late Map<String, dynamic> captured;
      final c = _client((req) async {
        captured = jsonDecode(req.body) as Map<String, dynamic>;
        return _json(200, {});
      });
      await c.rename('docs', '/old.txt', '/new.txt');
      expect(captured['from'], '/old.txt');
      expect(captured['to'], '/new.txt');
    });
  });

  // ─── copy ──────────────────────────────────────────────────────────────

  group('FileClient.copy', () {
    test('returns Ok on 201', () async {
      final c = _client((_) async =>
          http.Response(jsonEncode({'from': '/a', 'to': '/b'}), 201,
              headers: {'content-type': 'application/json'}));
      final result = await c.copy('docs', '/a', '/b');
      expect(result.isOk, isTrue);
    });

    test('returns Err on 409', () async {
      final c =
          _client((_) async => _error('ALREADY_EXISTS', 'Target exists', 409));
      final result = await c.copy('docs', '/a', '/existing');
      expect(result.isErr, isTrue);
      expect(result.errorCode, 'ALREADY_EXISTS');
    });
  });

  // ─── batchMove ─────────────────────────────────────────────────────────

  group('FileClient.batchMove', () {
    test('returns parsed results on 200', () async {
      final c = _client((_) async => _json(200, {
            'results': [
              {'item': '/a.txt', 'status': 200, 'message': 'moved'},
              {'item': '/b.txt', 'status': 200, 'message': 'moved'},
            ],
          }));
      final result = await c.batchMove('docs', ['/a.txt', '/b.txt'], '/dest');
      expect(result.isOk, isTrue);
      expect(result.unwrap.length, 2);
      expect(result.unwrap.every((r) => r.isSuccess), isTrue);
    });

    test('returns parsed results on 207 partial failure', () async {
      final c = _client((_) async => _json(207, {
            'results': [
              {'item': '/a.txt', 'status': 200, 'message': 'moved'},
              {'item': '/b.txt', 'status': 409, 'message': 'conflict'},
            ],
          }));
      final result = await c.batchMove('docs', ['/a.txt', '/b.txt'], '/dest');
      expect(result.isOk, isTrue);
      final statuses = result.unwrap.map((r) => r.status).toList();
      expect(statuses, containsAll([200, 409]));
    });
  });

  // ─── batchCopy ─────────────────────────────────────────────────────────

  group('FileClient.batchCopy', () {
    test('returns parsed results on 200', () async {
      final c = _client((_) async => _json(200, {
            'results': [
              {'item': '/x.txt', 'status': 201, 'message': 'copied'},
            ],
          }));
      final result = await c.batchCopy('docs', ['/x.txt'], '/cdest');
      expect(result.isOk, isTrue);
      expect(result.unwrap.first.key, '/x.txt');
    });
  });

  // ─── Error handling ────────────────────────────────────────────────────

  group('Error handling', () {
    test('network error returns NETWORK_ERROR', () async {
      final c = _client((_) async => throw SocketException('refused'));
      final result = await c.listRoots();
      expect(result.isErr, isTrue);
      expect(result.errorCode, 'NETWORK_ERROR');
    });

    test('malformed JSON response returns SERVER_ERROR', () async {
      final c = _client(
          (_) async => http.Response('not-json', 500));
      final result = await c.listRoots();
      expect(result.isErr, isTrue);
      expect(result.errorCode, 'SERVER_ERROR');
    });
  });
}
