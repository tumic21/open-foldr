import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:open_foldr/server/server.dart';
import 'package:open_foldr/models/shared_root.dart';
import 'package:open_foldr/models/role.dart';
import 'package:open_foldr/server/handlers/handlers.dart';

void main() {
  late OpenFoldrServer server;
  late Directory tempDir;
  const port = 17433;
  const base = 'http://127.0.0.1:$port/v1';
  var _pairCounter = 0;

  // Helper: pair and return a session token with the given role.
  Future<String> pairAs(Role role) async {
    final pairId = _pairCounter++;
    final secret = server.pairing.generateSecret();

    final reqRes = await http.post(
      Uri.parse('$base/auth/pair/request'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'deviceName': 'WriteTestClient-$pairId-${role.name}',
        'devicePublicKey': 'write-test-fp-$pairId-${role.name}',
        'pairingSecret': secret,
      }),
    );
    final requestId = (jsonDecode(reqRes.body))['pairRequestId'] as String;
    approvePairRequest(requestId, role: role);

    final completeRes = await http.post(
      Uri.parse('$base/auth/pair/complete'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'pairRequestId': requestId}),
    );
    return (jsonDecode(completeRes.body))['sessionToken'] as String;
  }

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('write_test_');
    File('${tempDir.path}/existing.txt').writeAsStringSync('original');

    server = OpenFoldrServer(port: port);
    server.roots.register(SharedRoot(
      alias: 'test',
      localPath: tempDir.path,
      minimumRole: Role.viewer,
    ));
    await server.start();
  });

  tearDownAll(() async {
    await server.stop();
    tempDir.deleteSync(recursive: true);
  });

  // ─── Metadata includes versionToken ──────────────────────────────────────

  group('File metadata', () {
    late String viewerToken;

    setUpAll(() async {
      viewerToken = await pairAs(Role.viewer);
    });

    test('GET /v1/roots/test/metadata includes versionToken', () async {
      final uri = Uri.parse('$base/roots/test/metadata')
          .replace(queryParameters: {'path': '/existing.txt'});
      final res = await http.get(
        uri,
        headers: {'authorization': 'Bearer $viewerToken'},
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['versionToken'], isA<String>());
      expect((body['versionToken'] as String).length, 16);
    });
  });

  // ─── Upload (PUT) ─────────────────────────────────────────────────────────

  group('File upload', () {
    late String editorToken;
    late String viewerToken;
    late String ownerToken;

    setUpAll(() async {
      editorToken = await pairAs(Role.editor);
      viewerToken = await pairAs(Role.viewer);
      ownerToken = await pairAs(Role.owner);
    });

    test('viewer cannot upload (403)', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/new_viewer.txt'});
      final res = await http.put(
        uri,
        headers: {
          'authorization': 'Bearer $viewerToken',
          'content-type': 'application/octet-stream',
        },
        body: 'data',
      );
      expect(res.statusCode, 403);
    });

    test('editor can create a new file', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/new_file.txt'});
      final res = await http.put(
        uri,
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/octet-stream',
        },
        body: 'hello phase 2',
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['versionToken'], isA<String>());

      // Verify file was written.
      expect(
        File('${tempDir.path}/new_file.txt').readAsStringSync(),
        'hello phase 2',
      );
    });

    test('update without If-Match returns 428', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/existing.txt'});
      final res = await http.put(
        uri,
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/octet-stream',
        },
        body: 'updated',
      );
      expect(res.statusCode, 428);
    });

    test('update with correct If-Match succeeds and returns new token',
        () async {
      // Get current token.
      final metaUri = Uri.parse('$base/roots/test/metadata')
          .replace(queryParameters: {'path': '/existing.txt'});
      final metaRes = await http.get(
        metaUri,
        headers: {'authorization': 'Bearer $editorToken'},
      );
      final currentToken =
          (jsonDecode(metaRes.body) as Map<String, dynamic>)['versionToken']
              as String;

      final putUri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/existing.txt'});
      final res = await http.put(
        putUri,
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/octet-stream',
          'if-match': currentToken,
        },
        body: 'updated content',
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['versionToken'], isNot(equals(currentToken)));
    });

    test('update with stale If-Match returns 409 with latest token', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/existing.txt'});
      final res = await http.put(
        uri,
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/octet-stream',
          'if-match': 'stale0000000000',
        },
        body: 'conflict attempt',
      );
      expect(res.statusCode, 409);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['versionToken'], isA<String>());
      expect(
        (body['error'] as Map<String, dynamic>)['code'],
        'VERSION_CONFLICT',
      );
    });

    test('owner can force-overwrite with If-Match: *', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/existing.txt'});
      final res = await http.put(
        uri,
        headers: {
          'authorization': 'Bearer $ownerToken',
          'content-type': 'application/octet-stream',
          'if-match': '*',
        },
        body: 'forced',
      );
      expect(res.statusCode, 200);
    });

    test('editor cannot force-overwrite with If-Match: *', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/existing.txt'});
      final res = await http.put(
        uri,
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/octet-stream',
          'if-match': '*',
        },
        body: 'forced by editor',
      );
      expect(res.statusCode, 403);
    });

    test('path traversal is rejected on upload', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '../../etc/evil'});
      final res = await http.put(
        uri,
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/octet-stream',
        },
        body: 'evil',
      );
      expect(res.statusCode, 400);
    });
  });

  // ─── Delete ────────────────────────────────────────────────────────────────

  group('File delete', () {
    late String ownerToken;
    late String editorToken;

    setUpAll(() async {
      ownerToken = await pairAs(Role.owner);
      editorToken = await pairAs(Role.editor);
    });

    setUp(() {
      // Ensure file exists before each delete test.
      File('${tempDir.path}/to_delete.txt').writeAsStringSync('bye');
    });

    test('editor cannot delete (403)', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/to_delete.txt'});
      final res = await http.delete(
        uri,
        headers: {'authorization': 'Bearer $editorToken'},
      );
      expect(res.statusCode, 403);
    });

    test('owner can delete a file', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/to_delete.txt'});
      final res = await http.delete(
        uri,
        headers: {'authorization': 'Bearer $ownerToken'},
      );
      expect(res.statusCode, 200);
      expect(File('${tempDir.path}/to_delete.txt').existsSync(), isFalse);
    });

    test('deleting non-existent file returns 404', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/ghost.txt'});
      final res = await http.delete(
        uri,
        headers: {'authorization': 'Bearer $ownerToken'},
      );
      expect(res.statusCode, 404);
    });

    test('path traversal rejected on delete', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '../../passwd'});
      final res = await http.delete(
        uri,
        headers: {'authorization': 'Bearer $ownerToken'},
      );
      expect(res.statusCode, 400);
    });

    test(
      'delete returns PERMISSION_DENIED when host cannot write target directory',
      () async {
        final lockedDir = Directory('${tempDir.path}/locked')..createSync();
        final lockedFile = File('${lockedDir.path}/locked.txt')
          ..writeAsStringSync('nope');

        final chmodResult = Process.runSync('chmod', ['0555', lockedDir.path]);
        expect(chmodResult.exitCode, 0,
            reason: 'chmod failed: ${chmodResult.stderr}');

        try {
          final uri = Uri.parse('$base/roots/test/file')
              .replace(queryParameters: {'path': '/locked/locked.txt'});
          final res = await http.delete(
            uri,
            headers: {'authorization': 'Bearer $ownerToken'},
          );

          expect(res.statusCode, 403);
          expect(lockedFile.existsSync(), isTrue);
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final error = body['error'] as Map<String, dynamic>;
          expect(error['code'], 'PERMISSION_DENIED');
        } finally {
          Process.runSync('chmod', ['0755', lockedDir.path]);
        }
      },
      skip: Platform.isWindows,
    );
  });

  // ─── Batch Delete ──────────────────────────────────────────────────────────

  group('Batch delete', () {
    late String ownerToken;

    setUpAll(() async {
      ownerToken = await pairAs(Role.owner);
    });

    setUp(() {
      File('${tempDir.path}/batch1.txt').writeAsStringSync('1');
      File('${tempDir.path}/batch2.txt').writeAsStringSync('2');
    });

    test('batch delete returns per-item results', () async {
      final uri = Uri.parse('$base/roots/test/batch/delete');
      final res = await http.post(
        uri,
        headers: {
          'authorization': 'Bearer $ownerToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'paths': ['/batch1.txt', '/batch2.txt', '/nonexistent.txt'],
        }),
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as List;
      expect(results.length, 3);

      final statuses = {
        for (final r in results) r['path'] as String: r['status'] as int
      };
      expect(statuses['/batch1.txt'], 200);
      expect(statuses['/batch2.txt'], 200);
      expect(statuses['/nonexistent.txt'], 404);
    });

    test('batch delete with traversal path returns per-item 400', () async {
      final uri = Uri.parse('$base/roots/test/batch/delete');
      final res = await http.post(
        uri,
        headers: {
          'authorization': 'Bearer $ownerToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'paths': ['/batch1.txt', '../../etc/passwd'],
        }),
      );
      expect(res.statusCode, 200);
      final results =
          (jsonDecode(res.body) as Map<String, dynamic>)['results'] as List;
      final traversalResult = results.firstWhere(
        (r) => (r['path'] as String).contains('etc'),
      );
      expect(traversalResult['status'], 400);
    });

    test(
      'batch delete returns per-item 403 when host lacks filesystem permission',
      () async {
        final lockedDir = Directory('${tempDir.path}/batch_locked')
          ..createSync();
        final lockedFile = File('${lockedDir.path}/blocked.txt')
          ..writeAsStringSync('blocked');

        final chmodResult = Process.runSync('chmod', ['0555', lockedDir.path]);
        expect(chmodResult.exitCode, 0,
            reason: 'chmod failed: ${chmodResult.stderr}');

        try {
          final uri = Uri.parse('$base/roots/test/batch/delete');
          final res = await http.post(
            uri,
            headers: {
              'authorization': 'Bearer $ownerToken',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'paths': ['/batch_locked/blocked.txt'],
            }),
          );

          expect(res.statusCode, 200);
          expect(lockedFile.existsSync(), isTrue);
          final body = jsonDecode(res.body) as Map<String, dynamic>;
          final results = body['results'] as List;
          expect(results, hasLength(1));
          final item = results.first as Map<String, dynamic>;
          expect(item['status'], 403);
          expect((item['message'] as String).toLowerCase(), contains('permission'));
        } finally {
          Process.runSync('chmod', ['0755', lockedDir.path]);
        }
      },
      skip: Platform.isWindows,
    );
  });
}
