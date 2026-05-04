import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:open_foldr/server/server.dart';
import 'package:open_foldr/models/shared_root.dart';
import 'package:open_foldr/models/role.dart';
import 'package:open_foldr/server/handlers/handlers.dart';

void main() {
  late OpenFoldrServer server;
  late Directory tempDir;
  const port = 17435;
  const base = 'http://127.0.0.1:$port/v1';

  Future<String> pairAs(Role role) async {
    final secret = server.pairing.generateSecret();
    final reqRes = await http.post(
      Uri.parse('$base/auth/pair/request'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'deviceName': 'Phase3Client',
        'devicePublicKey': '',
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
    tempDir = Directory.systemTemp.createTempSync('phase3_test_');
    File('${tempDir.path}/small.bin')
        .writeAsBytesSync(List.generate(16, (i) => i));
    File('${tempDir.path}/hello.txt').writeAsStringSync('Hello Phase 3');

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

  // ─── Range download (resumable download) ─────────────────────────────────

  group('Range download', () {
    late String token;

    setUpAll(() async {
      token = await pairAs(Role.viewer);
    });

    test('full download without Range returns 200 with accept-ranges', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/small.bin'});
      final res = await http.get(
        uri,
        headers: {'authorization': 'Bearer $token'},
      );
      expect(res.statusCode, 200);
      expect(res.headers['accept-ranges'], 'bytes');
      expect(res.bodyBytes.length, 16);
    });

    test('Range: bytes=0-7 returns 206 with first 8 bytes', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/small.bin'});
      final res = await http.get(
        uri,
        headers: {
          'authorization': 'Bearer $token',
          'range': 'bytes=0-7',
        },
      );
      expect(res.statusCode, 206);
      expect(res.headers['content-range'], 'bytes 0-7/16');
      expect(res.bodyBytes, List.generate(8, (i) => i));
    });

    test('Range: bytes=8-15 returns 206 with last 8 bytes', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/small.bin'});
      final res = await http.get(
        uri,
        headers: {
          'authorization': 'Bearer $token',
          'range': 'bytes=8-15',
        },
      );
      expect(res.statusCode, 206);
      expect(res.headers['content-range'], 'bytes 8-15/16');
      expect(res.bodyBytes, List.generate(8, (i) => i + 8));
    });

    test('suffix Range: bytes=-4 returns last 4 bytes', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/small.bin'});
      final res = await http.get(
        uri,
        headers: {
          'authorization': 'Bearer $token',
          'range': 'bytes=-4',
        },
      );
      expect(res.statusCode, 206);
      expect(res.bodyBytes.length, 4);
    });

    test('out-of-range returns 416', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/small.bin'});
      final res = await http.get(
        uri,
        headers: {
          'authorization': 'Bearer $token',
          'range': 'bytes=100-200',
        },
      );
      expect(res.statusCode, 416);
    });

    test('chunked reassembly equals full file', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/small.bin'});
      final chunks = <List<int>>[];
      for (var start = 0; start < 16; start += 4) {
        final end = start + 3;
        final res = await http.get(
          uri,
          headers: {
            'authorization': 'Bearer $token',
            'range': 'bytes=$start-$end',
          },
        );
        expect(res.statusCode, 206);
        chunks.add(res.bodyBytes);
      }
      final reassembled = chunks.expand((c) => c).toList();
      expect(reassembled, List.generate(16, (i) => i));
    });
  });

  // ─── Resumable upload protocol ────────────────────────────────────────────

  group('Resumable upload', () {
    late String editorToken;
    late String viewerToken;

    setUpAll(() async {
      editorToken = await pairAs(Role.editor);
      viewerToken = await pairAs(Role.viewer);
    });

    test('viewer cannot init upload (403)', () async {
      final res = await http.post(
        Uri.parse('$base/roots/test/upload/init'),
        headers: {
          'authorization': 'Bearer $viewerToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'path': '/viewer_upload.bin', 'size': 10}),
      );
      expect(res.statusCode, 403);
    });

    test('full resumable upload flow: init → chunks → complete', () async {
      // Prepare data (12 bytes, 3 chunks of 4).
      final data = Uint8List.fromList(List.generate(12, (i) => i * 2));
      final checksum = sha256.convert(data).toString();
      const chunkSize = 4;

      // Init.
      final initRes = await http.post(
        Uri.parse('$base/roots/test/upload/init'),
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'path': '/resumable_new.bin', 'size': data.length}),
      );
      expect(initRes.statusCode, 200);
      final initBody = jsonDecode(initRes.body) as Map<String, dynamic>;
      final uploadId = initBody['uploadId'] as String;
      expect(initBody['offset'], 0);

      // Upload chunks.
      for (var start = 0; start < data.length; start += chunkSize) {
        final end = start + chunkSize - 1 < data.length - 1
            ? start + chunkSize - 1
            : data.length - 1;
        final chunk = data.sublist(start, end + 1);
        final patchRes = await http.patch(
          Uri.parse('$base/roots/test/upload/$uploadId'),
          headers: {
            'authorization': 'Bearer $editorToken',
            'content-type': 'application/octet-stream',
            'content-range': 'bytes $start-$end/${data.length}',
          },
          body: chunk,
        );
        expect(patchRes.statusCode, 200,
            reason: 'chunk $start-$end failed: ${patchRes.body}');
        final patchBody = jsonDecode(patchRes.body) as Map<String, dynamic>;
        expect(patchBody['offset'], end + 1);
      }

      // Query offset endpoint.
      final offsetRes = await http.get(
        Uri.parse('$base/roots/test/upload/$uploadId/offset'),
        headers: {'authorization': 'Bearer $editorToken'},
      );
      expect(offsetRes.statusCode, 200);
      expect(
        (jsonDecode(offsetRes.body) as Map<String, dynamic>)['offset'],
        data.length,
      );

      // Complete.
      final completeRes = await http.post(
        Uri.parse('$base/roots/test/upload/$uploadId/complete'),
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'sha256': checksum}),
      );
      expect(completeRes.statusCode, 200);
      expect(
        (jsonDecode(completeRes.body) as Map<String, dynamic>)['versionToken'],
        isA<String>(),
      );

      // Verify file content.
      expect(
        File('${tempDir.path}/resumable_new.bin').readAsBytesSync(),
        data,
      );
    });

    test('wrong checksum on complete returns 422', () async {
      final data = Uint8List.fromList([1, 2, 3, 4]);
      final initRes = await http.post(
        Uri.parse('$base/roots/test/upload/init'),
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'path': '/checksum_fail.bin', 'size': 4}),
      );
      final uploadId =
          (jsonDecode(initRes.body) as Map<String, dynamic>)['uploadId']
              as String;

      await http.patch(
        Uri.parse('$base/roots/test/upload/$uploadId'),
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/octet-stream',
          'content-range': 'bytes 0-3/4',
        },
        body: data,
      );

      final completeRes = await http.post(
        Uri.parse('$base/roots/test/upload/$uploadId/complete'),
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'sha256': 'deadbeefdeadbeef' * 4}),
      );
      expect(completeRes.statusCode, 422);
      expect(
        (jsonDecode(completeRes.body) as Map<String, dynamic>)['error']
            ['code'],
        'CHECKSUM_MISMATCH',
      );
    });

    test('second init for same path returns existing uploadId and offset',
        () async {
      final initRes1 = await http.post(
        Uri.parse('$base/roots/test/upload/init'),
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'path': '/resume_same.bin', 'size': 100}),
      );
      final id1 = (jsonDecode(initRes1.body))['uploadId'] as String;

      final initRes2 = await http.post(
        Uri.parse('$base/roots/test/upload/init'),
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'path': '/resume_same.bin', 'size': 100}),
      );
      final id2 = (jsonDecode(initRes2.body))['uploadId'] as String;
      expect(id2, id1);

      // Cancel to clean up.
      await http.delete(
        Uri.parse('$base/roots/test/upload/$id1'),
        headers: {'authorization': 'Bearer $editorToken'},
      );
    });

    test('cancel removes the upload session', () async {
      final initRes = await http.post(
        Uri.parse('$base/roots/test/upload/init'),
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'path': '/to_cancel.bin', 'size': 10}),
      );
      final uploadId = (jsonDecode(initRes.body))['uploadId'] as String;

      final cancelRes = await http.delete(
        Uri.parse('$base/roots/test/upload/$uploadId'),
        headers: {'authorization': 'Bearer $editorToken'},
      );
      expect(cancelRes.statusCode, 200);

      // Querying offset after cancel should return 404.
      final offsetRes = await http.get(
        Uri.parse('$base/roots/test/upload/$uploadId/offset'),
        headers: {'authorization': 'Bearer $editorToken'},
      );
      expect(offsetRes.statusCode, 404);
    });

    test('offset mismatch in chunk returns 409 with current offset', () async {
      final data = Uint8List.fromList(List.generate(8, (i) => i));
      final initRes = await http.post(
        Uri.parse('$base/roots/test/upload/init'),
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'path': '/offset_mismatch.bin', 'size': 8}),
      );
      final uploadId = (jsonDecode(initRes.body))['uploadId'] as String;

      // Send chunk starting at wrong offset.
      final patchRes = await http.patch(
        Uri.parse('$base/roots/test/upload/$uploadId'),
        headers: {
          'authorization': 'Bearer $editorToken',
          'content-type': 'application/octet-stream',
          'content-range': 'bytes 4-7/8',
        },
        body: data.sublist(4),
      );
      expect(patchRes.statusCode, 409);
      final body = jsonDecode(patchRes.body) as Map<String, dynamic>;
      expect(body['offset'], 0);
      expect(body['error']['code'], 'OFFSET_MISMATCH');

      // Cleanup.
      await http.delete(
        Uri.parse('$base/roots/test/upload/$uploadId'),
        headers: {'authorization': 'Bearer $editorToken'},
      );
    });
  });
}
