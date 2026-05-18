import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:open_foldr/models/role.dart';
import 'package:open_foldr/models/shared_root.dart';
import 'package:open_foldr/server/handlers/handlers.dart';
import 'package:open_foldr/server/server.dart';

void main() {
  late OpenFoldrServer server;
  late Directory tempDir;
  const port = 17439;
  const base = 'http://127.0.0.1:$port/v1';

  Future<String> pairViewerToken() async {
    final secret = server.pairing.generateSecret();
    final reqRes = await http.post(
      Uri.parse('$base/auth/pair/request'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({
        'deviceName': 'ThumbnailTestClient',
        'devicePublicKey': '',
        'pairingSecret': secret,
      }),
    );
    expect(reqRes.statusCode, 200, reason: 'pair/request failed');

    final requestId =
        (jsonDecode(reqRes.body) as Map<String, dynamic>)['pairRequestId']
            as String;
    approvePairRequest(requestId, role: Role.viewer);

    final completeRes = await http.post(
      Uri.parse('$base/auth/pair/complete'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'pairRequestId': requestId}),
    );
    expect(completeRes.statusCode, 200, reason: 'pair/complete failed');

    return (jsonDecode(completeRes.body) as Map<String, dynamic>)[
            'sessionToken']
        as String;
  }

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('thumbnail_test_');

    final src = img.Image(width: 640, height: 480);
    img.fill(src, color: img.ColorRgb8(32, 120, 220));
    final png = img.encodePng(src);
    await File('${tempDir.path}/photo.png').writeAsBytes(png);
    await File('${tempDir.path}/note.txt').writeAsString('not an image');

    server = OpenFoldrServer(port: port);
    server.roots.register(
      SharedRoot(
        alias: 'test',
        localPath: tempDir.path,
        minimumRole: Role.viewer,
      ),
    );
    await server.start();
  });

  tearDownAll(() async {
    await server.stop();
    tempDir.deleteSync(recursive: true);
  });

  test('GET /v1/roots/test/thumbnail returns resized image bytes', () async {
    final token = await pairViewerToken();
    final uri = Uri.parse('$base/roots/test/thumbnail').replace(
      queryParameters: {
        'path': '/photo.png',
        'w': '48',
        'h': '48',
        'fit': 'cover',
      },
    );

    final res = await http.get(
      uri,
      headers: {'authorization': 'Bearer $token'},
    );

    expect(res.statusCode, 200);
    expect(res.headers['content-type'], anyOf('image/png', 'image/jpeg'));
    expect(res.bodyBytes, isNotEmpty);

    final decoded = img.decodeImage(res.bodyBytes);
    expect(decoded, isNotNull);
    expect(decoded!.width, 48);
    expect(decoded.height, 48);
    expect(res.headers['etag'], isNotNull);
  });

  test('GET /thumbnail returns 304 when if-none-match matches', () async {
    final token = await pairViewerToken();
    final uri = Uri.parse('$base/roots/test/thumbnail').replace(
      queryParameters: {
        'path': '/photo.png',
        'w': '48',
        'h': '48',
        'fit': 'cover',
      },
    );

    final first = await http.get(
      uri,
      headers: {'authorization': 'Bearer $token'},
    );
    expect(first.statusCode, 200);
    final etag = first.headers['etag'];
    expect(etag, isNotNull);

    final second = await http.get(
      uri,
      headers: {
        'authorization': 'Bearer $token',
        'if-none-match': etag!,
      },
    );
    expect(second.statusCode, 304);
    expect(second.bodyBytes, isEmpty);
  });

  test('GET /thumbnail rejects non-image files with 415', () async {
    final token = await pairViewerToken();
    final uri = Uri.parse('$base/roots/test/thumbnail').replace(
      queryParameters: {'path': '/note.txt', 'w': '48', 'h': '48'},
    );

    final res = await http.get(
      uri,
      headers: {'authorization': 'Bearer $token'},
    );

    expect(res.statusCode, 415);
    final body = jsonDecode(res.body) as Map<String, dynamic>;
    expect(body['error']['code'], 'UNSUPPORTED_MEDIA_TYPE');
  });
}
