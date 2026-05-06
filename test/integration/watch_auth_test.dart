import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_foldr/models/role.dart';
import 'package:open_foldr/models/shared_root.dart';
import 'package:open_foldr/server/handlers/handlers.dart';
import 'package:open_foldr/server/server.dart';

void main() {
  late OpenFoldrServer server;
  late Directory tempDir;
  const port = 17436;
  const base = 'http://127.0.0.1:$port/v1';

  Future<String> pairAs(Role role) async {
    final secret = server.pairing.generateSecret();

    final client = HttpClient();
    final req = await client.postUrl(Uri.parse('$base/auth/pair/request'));
    req.headers.contentType = ContentType.json;
    req.write(jsonEncode({
      'deviceName': 'WatchAuthClient',
      'devicePublicKey': '',
      'pairingSecret': secret,
    }));
    final reqRes = await req.close();
    final reqBody = jsonDecode(await utf8.decodeStream(reqRes))
        as Map<String, dynamic>;
    final requestId = reqBody['pairRequestId'] as String;
    approvePairRequest(requestId, role: role);

    final complete = await client.postUrl(Uri.parse('$base/auth/pair/complete'));
    complete.headers.contentType = ContentType.json;
    complete.write(jsonEncode({'pairRequestId': requestId}));
    final completeRes = await complete.close();
    final completeBody = jsonDecode(await utf8.decodeStream(completeRes))
        as Map<String, dynamic>;
    client.close();
    return completeBody['sessionToken'] as String;
  }

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('watch_auth_test_');
    File('${tempDir.path}/hello.txt').writeAsStringSync('hello');

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

  test('watch websocket accepts query-token authentication', () async {
    final token = await pairAs(Role.viewer);
    final socket = await WebSocket.connect(
      'ws://127.0.0.1:$port/v1/roots/test/watch?path=%2F&token=$token',
    );

    expect(socket.readyState, WebSocket.open);
    await socket.close();
  });
}