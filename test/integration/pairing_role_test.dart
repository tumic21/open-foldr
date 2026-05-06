import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:open_foldr/models/role.dart';
import 'package:open_foldr/models/shared_root.dart';
import 'package:open_foldr/server/server.dart';

void main() {
  late OpenFoldrServer server;
  late Directory tempDir;
  const port = 17437;
  const base = 'http://127.0.0.1:$port/v1';

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('pairing_role_test_');
    File('${tempDir.path}/hello.txt').writeAsStringSync('hello');

    server = OpenFoldrServer(port: port);
    server.roots.register(SharedRoot(
      alias: 'test',
      localPath: tempDir.path,
      minimumRole: Role.owner,
    ));
    await server.start();
  });

  tearDownAll(() async {
    await server.stop();
    tempDir.deleteSync(recursive: true);
  });

  test('pairing defaults new session role to highest shared-root role', () async {
    final secret = server.pairing.generateSecret();

    final requestRes = await http.post(
      Uri.parse('$base/auth/pair/request'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'deviceName': 'OwnerClient',
        'devicePublicKey': '',
        'pairingSecret': secret,
      }),
    );
    expect(requestRes.statusCode, 200);

    final requestId =
        (jsonDecode(requestRes.body) as Map<String, dynamic>)['pairRequestId']
            as String;

    final completeRes = await http.post(
      Uri.parse('$base/auth/pair/complete'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'pairRequestId': requestId}),
    );
    expect(completeRes.statusCode, 200);

    final body = jsonDecode(completeRes.body) as Map<String, dynamic>;
    expect(body['role'], 'owner');
  });
}
