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
  const port = 17432;
  const base = 'http://127.0.0.1:$port/v1';

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('browse_test_');
    File('${tempDir.path}/hello.txt').writeAsStringSync('hello');
    Directory('${tempDir.path}/sub').createSync();

    server = OpenFoldrServer(port: port);
    server.roots.register(SharedRoot(
      alias: 'test',
      localPath: tempDir.path,
      minimumRole: Role.viewer,
    ));
    await server.start();

    // Auto-approve pending requests for test purposes.
  });

  tearDownAll(() async {
    await server.stop();
    tempDir.deleteSync(recursive: true);
  });

  group('Health', () {
    test('GET /v1/health returns ok', () async {
      final res = await http.get(Uri.parse('$base/health'));
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body);
      expect(body['status'], 'ok');
    });
  });

  group('Authentication', () {
    test('protected endpoint without token returns 401', () async {
      final res = await http.get(Uri.parse('$base/roots'));
      expect(res.statusCode, 401);
    });

    test('protected endpoint with invalid token returns 401', () async {
      final res = await http.get(
        Uri.parse('$base/roots'),
        headers: {'authorization': 'Bearer bad-token'},
      );
      expect(res.statusCode, 401);
    });
  });

  group('Browse with valid session', () {
    late String sessionToken;

    setUpAll(() async {
      // Pair a client and get a session token.
      final secret = server.pairing.generateSecret();

      final reqRes = await http.post(
        Uri.parse('$base/auth/pair/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'deviceName': 'TestClient',
          'devicePublicKey': '',
          'pairingSecret': secret,
        }),
      );
      expect(reqRes.statusCode, 200);
      final requestId = (jsonDecode(reqRes.body))['pairRequestId'] as String;

      // Approve from host side.
      approvePairRequest(requestId, role: Role.viewer);

      final completeRes = await http.post(
        Uri.parse('$base/auth/pair/complete'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'pairRequestId': requestId}),
      );
      expect(completeRes.statusCode, 200);
      sessionToken = (jsonDecode(completeRes.body))['sessionToken'] as String;
    });

    test('GET /v1/roots returns registered roots', () async {
      final res = await http.get(
        Uri.parse('$base/roots'),
        headers: {'authorization': 'Bearer $sessionToken'},
      );
      expect(res.statusCode, 200);
      final body = jsonDecode(res.body);
      final roots = body['roots'] as List;
      expect(roots.any((r) => r['alias'] == 'test'), isTrue);
    });

    test('GET /v1/roots/test/entries lists directory contents', () async {
      final uri = Uri.parse('$base/roots/test/entries')
          .replace(queryParameters: {'path': '/'});
      final res = await http.get(
        uri,
        headers: {'authorization': 'Bearer $sessionToken'},
      );
      expect(res.statusCode, 200);
      final entries = (jsonDecode(res.body))['entries'] as List;
      expect(entries.any((e) => e['name'] == 'hello.txt'), isTrue);
    });

    test('GET /v1/roots/test/file downloads file content', () async {
      final uri = Uri.parse('$base/roots/test/file')
          .replace(queryParameters: {'path': '/hello.txt'});
      final res = await http.get(
        uri,
        headers: {'authorization': 'Bearer $sessionToken'},
      );
      expect(res.statusCode, 200);
      expect(res.body, 'hello');
    });

    test('path traversal is rejected', () async {
      final uri = Uri.parse('$base/roots/test/entries')
          .replace(queryParameters: {'path': '../../etc/passwd'});
      final res = await http.get(
        uri,
        headers: {'authorization': 'Bearer $sessionToken'},
      );
      expect(res.statusCode, 400);
      final body = jsonDecode(res.body);
      expect(body['error']['code'], 'INVALID_ARGUMENT');
    });
  });
}
