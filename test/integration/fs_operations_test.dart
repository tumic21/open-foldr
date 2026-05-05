/// Integration tests for Phase 1 server endpoints:
///   POST /v1/roots/<alias>/mkdir
///   POST /v1/roots/<alias>/rename
///   POST /v1/roots/<alias>/copy
///   POST /v1/roots/<alias>/batch/move
///   POST /v1/roots/<alias>/batch/copy
///
/// Starts a real OpenFoldrServer on a fixed port, exercises each handler,
/// and asserts HTTP status codes and filesystem side-effects.

import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:open_foldr/models/role.dart';
import 'package:open_foldr/models/shared_root.dart';
import 'package:open_foldr/server/handlers/handlers.dart';
import 'package:open_foldr/server/server.dart';

void main() {
  late OpenFoldrServer server;
  late Directory tempDir;
  const port = 17440;
  const base = 'http://127.0.0.1:$port/v1';

  // ─── Helpers ─────────────────────────────────────────────────────────────

  Future<String> pairAs(Role role) async {
    final secret = server.pairing.generateSecret();

    final reqRes = await http.post(
      Uri.parse('$base/auth/pair/request'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'deviceName': 'FsOpsTestClient',
        'devicePublicKey': '',
        'pairingSecret': secret,
      }),
    );
    expect(reqRes.statusCode, 200,
        reason: 'pair/request failed: ${reqRes.body}');
    final requestId =
        (jsonDecode(reqRes.body) as Map<String, dynamic>)['pairRequestId']
            as String;
    approvePairRequest(requestId, role: role);

    final completeRes = await http.post(
      Uri.parse('$base/auth/pair/complete'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'pairRequestId': requestId}),
    );
    expect(completeRes.statusCode, 200,
        reason: 'pair/complete failed: ${completeRes.body}');
    return (jsonDecode(completeRes.body) as Map<String, dynamic>)['sessionToken']
        as String;
  }

  Future<http.Response> fsPost(
    String path,
    Map<String, dynamic> body,
    String token,
  ) =>
      http.post(
        Uri.parse('$base/roots/test/$path'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

  // ─── Setup / teardown ─────────────────────────────────────────────────────

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('fs_ops_test_');
    server = OpenFoldrServer(port: port);
    server.roots.register(SharedRoot(
      alias: 'test',
      localPath: tempDir.path,
      minimumRole: Role.viewer,
    ));
    await server.start();
  });

  setUp(() {
    // Clean the sandbox between tests so state does not bleed.
    for (final e in tempDir.listSync()) {
      if (e is File) e.deleteSync();
      if (e is Directory) e.deleteSync(recursive: true);
    }
    // Seed a known file that tests can operate on.
    File('${tempDir.path}/seed.txt').writeAsStringSync('hello');
    Directory('${tempDir.path}/subdir').createSync();
    File('${tempDir.path}/subdir/nested.txt').writeAsStringSync('nested');
  });

  tearDownAll(() async {
    await server.stop();
    tempDir.deleteSync(recursive: true);
  });

  // ─── mkdir ────────────────────────────────────────────────────────────────

  group('mkdir', () {
    late String editorToken;
    late String viewerToken;

    setUpAll(() async {
      editorToken = await pairAs(Role.editor);
      viewerToken = await pairAs(Role.viewer);
    });

    test('editor can create a new directory (201)', () async {
      final res = await fsPost('mkdir', {'path': '/newdir'}, editorToken);
      expect(res.statusCode, 201);
      expect(Directory('${tempDir.path}/newdir').existsSync(), isTrue);
    });

    test('creates nested directories in a single call (201)', () async {
      final res =
          await fsPost('mkdir', {'path': '/a/b/c'}, editorToken);
      expect(res.statusCode, 201);
      expect(Directory('${tempDir.path}/a/b/c').existsSync(), isTrue);
    });

    test('returns 409 when directory already exists', () async {
      final res = await fsPost('mkdir', {'path': '/subdir'}, editorToken);
      expect(res.statusCode, 409);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final error = body['error'] as Map<String, dynamic>;
      expect(error['code'], 'ALREADY_EXISTS');
    });

    test('viewer cannot create a directory (403)', () async {
      final res =
          await fsPost('mkdir', {'path': '/viewerdir'}, viewerToken);
      expect(res.statusCode, 403);
    });

    test('rejects path traversal (400)', () async {
      final res =
          await fsPost('mkdir', {'path': '/../../escape'}, editorToken);
      expect(res.statusCode, 400);
    });

    test('missing path field returns 400', () async {
      final res = await fsPost('mkdir', {}, editorToken);
      expect(res.statusCode, 400);
    });
  });

  // ─── rename ───────────────────────────────────────────────────────────────

  group('rename', () {
    late String editorToken;
    late String viewerToken;

    setUpAll(() async {
      editorToken = await pairAs(Role.editor);
      viewerToken = await pairAs(Role.viewer);
    });

    test('editor can rename a file (200)', () async {
      final res = await fsPost(
          'rename', {'from': '/seed.txt', 'to': '/renamed.txt'}, editorToken);
      expect(res.statusCode, 200);
      expect(File('${tempDir.path}/renamed.txt').existsSync(), isTrue);
      expect(File('${tempDir.path}/seed.txt').existsSync(), isFalse);
    });

    test('editor can rename a directory (200)', () async {
      final res = await fsPost(
          'rename', {'from': '/subdir', 'to': '/subdir_renamed'}, editorToken);
      expect(res.statusCode, 200);
      expect(Directory('${tempDir.path}/subdir_renamed').existsSync(), isTrue);
      expect(Directory('${tempDir.path}/subdir').existsSync(), isFalse);
    });

    test('returns 404 when source does not exist', () async {
      final res = await fsPost(
          'rename', {'from': '/missing.txt', 'to': '/other.txt'}, editorToken);
      expect(res.statusCode, 404);
    });

    test('returns 409 when target already exists', () async {
      File('${tempDir.path}/other.txt').writeAsStringSync('x');
      final res = await fsPost(
          'rename', {'from': '/seed.txt', 'to': '/other.txt'}, editorToken);
      expect(res.statusCode, 409);
    });

    test('viewer cannot rename (403)', () async {
      final res = await fsPost(
          'rename', {'from': '/seed.txt', 'to': '/renamed.txt'}, viewerToken);
      expect(res.statusCode, 403);
    });

    test('missing from/to returns 400', () async {
      final res = await fsPost('rename', {'from': '/seed.txt'}, editorToken);
      expect(res.statusCode, 400);
    });
  });

  // ─── copy ─────────────────────────────────────────────────────────────────

  group('copy', () {
    late String editorToken;
    late String viewerToken;

    setUpAll(() async {
      editorToken = await pairAs(Role.editor);
      viewerToken = await pairAs(Role.viewer);
    });

    test('editor can copy a file (201)', () async {
      final res = await fsPost(
          'copy', {'from': '/seed.txt', 'to': '/seed_copy.txt'}, editorToken);
      expect(res.statusCode, 201);
      expect(File('${tempDir.path}/seed_copy.txt').existsSync(), isTrue);
      // Original must still exist.
      expect(File('${tempDir.path}/seed.txt').existsSync(), isTrue);
    });

    test('copy preserves file content', () async {
      await fsPost(
          'copy', {'from': '/seed.txt', 'to': '/copy_check.txt'}, editorToken);
      final content =
          File('${tempDir.path}/copy_check.txt').readAsStringSync();
      expect(content, 'hello');
    });

    test('editor can copy a directory (201)', () async {
      final res = await fsPost(
          'copy', {'from': '/subdir', 'to': '/subdir_copy'}, editorToken);
      expect(res.statusCode, 201);
      expect(Directory('${tempDir.path}/subdir_copy').existsSync(), isTrue);
      expect(
        File('${tempDir.path}/subdir_copy/nested.txt').existsSync(),
        isTrue,
      );
    });

    test('returns 404 when source does not exist', () async {
      final res = await fsPost(
          'copy', {'from': '/missing.txt', 'to': '/out.txt'}, editorToken);
      expect(res.statusCode, 404);
    });

    test('returns 409 when target already exists', () async {
      final res = await fsPost(
          'copy', {'from': '/seed.txt', 'to': '/subdir'}, editorToken);
      expect(res.statusCode, 409);
    });

    test('viewer cannot copy (403)', () async {
      final res = await fsPost(
          'copy', {'from': '/seed.txt', 'to': '/x.txt'}, viewerToken);
      expect(res.statusCode, 403);
    });
  });

  // ─── batch/move ───────────────────────────────────────────────────────────

  group('batch/move', () {
    late String editorToken;
    late String viewerToken;

    setUpAll(() async {
      editorToken = await pairAs(Role.editor);
      viewerToken = await pairAs(Role.viewer);
    });

    test('moves multiple files into destination (200)', () async {
      File('${tempDir.path}/a.txt').writeAsStringSync('a');
      File('${tempDir.path}/b.txt').writeAsStringSync('b');
      Directory('${tempDir.path}/dest').createSync();

      final res = await fsPost(
        'batch/move',
        {
          'items': ['/a.txt', '/b.txt'],
          'destination': '/dest',
        },
        editorToken,
      );
      expect(res.statusCode, 200);
      expect(File('${tempDir.path}/dest/a.txt').existsSync(), isTrue);
      expect(File('${tempDir.path}/dest/b.txt').existsSync(), isTrue);
      expect(File('${tempDir.path}/a.txt').existsSync(), isFalse);
    });

    test('creates destination directory if missing', () async {
      File('${tempDir.path}/c.txt').writeAsStringSync('c');
      final res = await fsPost(
        'batch/move',
        {'items': ['/c.txt'], 'destination': '/newdest'},
        editorToken,
      );
      expect(res.statusCode, 200);
      expect(File('${tempDir.path}/newdest/c.txt').existsSync(), isTrue);
    });

    test('partial failure returns 207 with per-item results', () async {
      File('${tempDir.path}/exists.txt').writeAsStringSync('x');
      Directory('${tempDir.path}/pdest').createSync();
      // Pre-place a conflict at the destination.
      File('${tempDir.path}/pdest/exists.txt').writeAsStringSync('conflict');

      final res = await fsPost(
        'batch/move',
        {
          'items': ['/exists.txt', '/seed.txt'],
          'destination': '/pdest',
        },
        editorToken,
      );
      expect(res.statusCode, 207);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as List;
      final statuses = results.map((r) => (r as Map)['status']).toList();
      expect(statuses, contains(409)); // conflict
      expect(statuses, contains(200)); // success
    });

    test('viewer cannot batch/move (403)', () async {
      final res = await fsPost(
        'batch/move',
        {'items': ['/seed.txt'], 'destination': '/dest'},
        viewerToken,
      );
      expect(res.statusCode, 403);
    });
  });

  // ─── batch/copy ───────────────────────────────────────────────────────────

  group('batch/copy', () {
    late String editorToken;
    late String viewerToken;

    setUpAll(() async {
      editorToken = await pairAs(Role.editor);
      viewerToken = await pairAs(Role.viewer);
    });

    test('copies multiple files into destination (200)', () async {
      File('${tempDir.path}/x.txt').writeAsStringSync('x');
      File('${tempDir.path}/y.txt').writeAsStringSync('y');
      Directory('${tempDir.path}/cdest').createSync();

      final res = await fsPost(
        'batch/copy',
        {
          'items': ['/x.txt', '/y.txt'],
          'destination': '/cdest',
        },
        editorToken,
      );
      expect(res.statusCode, 200);
      expect(File('${tempDir.path}/cdest/x.txt').existsSync(), isTrue);
      expect(File('${tempDir.path}/cdest/y.txt').existsSync(), isTrue);
      // Originals must still exist.
      expect(File('${tempDir.path}/x.txt').existsSync(), isTrue);
    });

    test('partial failure returns 207', () async {
      File('${tempDir.path}/cp_a.txt').writeAsStringSync('a');
      Directory('${tempDir.path}/cpdest').createSync();
      File('${tempDir.path}/cpdest/cp_a.txt').writeAsStringSync('conflict');

      final res = await fsPost(
        'batch/copy',
        {
          'items': ['/cp_a.txt', '/seed.txt'],
          'destination': '/cpdest',
        },
        editorToken,
      );
      expect(res.statusCode, 207);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final results = body['results'] as List;
      final statuses = results.map((r) => (r as Map)['status'] as int).toSet();
      expect(statuses, contains(409));
      expect(statuses.any((s) => s == 200 || s == 201), isTrue);
    });

    test('viewer cannot batch/copy (403)', () async {
      final res = await fsPost(
        'batch/copy',
        {'items': ['/seed.txt'], 'destination': '/cdest'},
        viewerToken,
      );
      expect(res.statusCode, 403);
    });
  });
}
