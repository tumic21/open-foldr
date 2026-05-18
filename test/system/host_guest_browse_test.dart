import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:open_foldr/server/server.dart';
import 'package:open_foldr/models/shared_root.dart';
import 'package:open_foldr/models/role.dart';
import 'package:open_foldr/server/handlers/handlers.dart';

/// System test: full host-guest browse workflow end-to-end.
void main() {
  late OpenFoldrServer host;
  late Directory sharedDir;
  const port = 17434;
  const base = 'http://127.0.0.1:$port/v1';

  setUpAll(() async {
    sharedDir = Directory.systemTemp.createTempSync('system_test_');
    File('${sharedDir.path}/readme.txt')
        .writeAsStringSync('OpenFoldr Phase 1');
    Directory('${sharedDir.path}/docs').createSync();
    File('${sharedDir.path}/docs/notes.md').writeAsStringSync('# Notes');

    host = OpenFoldrServer(port: port);
    host.roots.register(SharedRoot(
      alias: 'share',
      localPath: sharedDir.path,
      minimumRole: Role.viewer,
    ));
    await host.start();
  });

  tearDownAll(() async {
    await host.stop();
    sharedDir.deleteSync(recursive: true);
  });

  test('Host starts and responds to health check', () async {
    final res = await http.get(Uri.parse('$base/health'));
    expect(res.statusCode, 200);
  });

  test('Guest completes full browse workflow', () async {
    // 1. Guest pairs
    final secret = host.pairing.generateSecret();
    final reqRes = await http.post(
      Uri.parse('$base/auth/pair/request'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'deviceName': 'GuestDevice',
        'devicePublicKey': '',
        'pairingSecret': secret,
      }),
    );
    expect(reqRes.statusCode, 200);
    final requestId = (jsonDecode(reqRes.body))['pairRequestId'] as String;
    approvePairRequest(requestId, role: Role.viewer);

    final completeRes = await http.post(
      Uri.parse('$base/auth/pair/complete'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'pairRequestId': requestId}),
    );
    expect(completeRes.statusCode, 200);
    final token = (jsonDecode(completeRes.body))['sessionToken'] as String;

    // 2. Guest lists roots
    final rootsRes = await http.get(
      Uri.parse('$base/roots'),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(rootsRes.statusCode, 200);
    final roots = (jsonDecode(rootsRes.body))['roots'] as List;
    expect(roots.length, 1);
    expect(roots.first['alias'], 'share');

    // 3. Guest browses root directory
    final entriesRes = await http.get(
      Uri.parse('$base/roots/share/entries')
          .replace(queryParameters: {'path': '/'}),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(entriesRes.statusCode, 200);
    final entries = (jsonDecode(entriesRes.body))['entries'] as List;
    final names = entries.map((e) => e['name']).toList();
    expect(names, containsAll(['readme.txt', 'docs']));

    // 4. Guest downloads a file
    final fileRes = await http.get(
      Uri.parse('$base/roots/share/file')
          .replace(queryParameters: {'path': '/readme.txt'}),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(fileRes.statusCode, 200);
    expect(fileRes.body, 'OpenFoldr Phase 1');

    // 5. Guest browses sub-directory
    final subRes = await http.get(
      Uri.parse('$base/roots/share/entries')
          .replace(queryParameters: {'path': '/docs'}),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(subRes.statusCode, 200);
    final subEntries = (jsonDecode(subRes.body))['entries'] as List;
    expect(subEntries.any((e) => e['name'] == 'notes.md'), isTrue);
  });

  test('Viewer role cannot access non-existent write endpoint', () async {
    // Write endpoints are not exposed in Phase 1; any unknown route returns 404.
    final res = await http.put(
      Uri.parse('$base/roots/share/file')
          .replace(queryParameters: {'path': '/new.txt'}),
      headers: {'authorization': 'Bearer invalid', 'content-type': 'application/json'},
      body: 'data',
    );
    expect(res.statusCode, anyOf(401, 404, 405));
  });

  test('Path traversal is blocked at system level', () async {
    final secret = host.pairing.generateSecret();
    final reqRes = await http.post(
      Uri.parse('$base/auth/pair/request'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'deviceName': 'AttackerDevice',
        'devicePublicKey': '',
        'pairingSecret': secret,
      }),
    );
    final requestId = (jsonDecode(reqRes.body))['pairRequestId'] as String;
    approvePairRequest(requestId, role: Role.viewer);

    final completeRes = await http.post(
      Uri.parse('$base/auth/pair/complete'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'pairRequestId': requestId}),
    );
    final token = (jsonDecode(completeRes.body))['sessionToken'] as String;

    final traversalRes = await http.get(
      Uri.parse('$base/roots/share/entries')
          .replace(queryParameters: {'path': '../../../etc'}),
      headers: {'authorization': 'Bearer $token'},
    );
    expect(traversalRes.statusCode, 400);
    final body = jsonDecode(traversalRes.body);
    expect(body['error']['code'], 'INVALID_ARGUMENT');
  });
}
