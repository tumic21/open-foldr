import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:open_foldr/server/server.dart';
import 'package:open_foldr/server/handlers/handlers.dart';

void main() {
  late OpenFoldrServer server;
  const port = 17436;
  const base = 'http://127.0.0.1:$port/v1';

  setUpAll(() async {
    server = OpenFoldrServer(port: port);
    await server.start();
  });

  tearDownAll(() => server.stop());

  group('Pairing flow', () {
    test('rejects unknown pairing secret', () async {
      server.pairing.generateSecret();
      final res = await http.post(
        Uri.parse('$base/auth/pair/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'deviceName': 'TestDevice',
          'devicePublicKey': '',
          'pairingSecret': '000000',
        }),
      );
      expect(res.statusCode, 401);
    });

    test('full pairing flow succeeds', () async {
      final secret = server.pairing.generateSecret();

      final reqRes = await http.post(
        Uri.parse('$base/auth/pair/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'deviceName': 'Phone',
          'devicePublicKey': '',
          'pairingSecret': secret,
        }),
      );
      expect(reqRes.statusCode, 200);
      final requestId = (jsonDecode(reqRes.body))['pairRequestId'] as String;

      final completeRes = await http.post(
        Uri.parse('$base/auth/pair/complete'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'pairRequestId': requestId}),
      );
      expect(completeRes.statusCode, 200);
      final body = jsonDecode(completeRes.body);
      expect(body['sessionToken'], isA<String>());
      expect(body['deviceToken'], isA<String>());
      expect(body['role'], 'viewer');
    });

    test('denied pair request returns 404', () async {
      final secret = server.pairing.generateSecret();
      final reqRes = await http.post(
        Uri.parse('$base/auth/pair/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'deviceName': 'Rogue',
          'devicePublicKey': '',
          'pairingSecret': secret,
        }),
      );
      final requestId = (jsonDecode(reqRes.body))['pairRequestId'] as String;
      denyPairRequest(requestId);

      final completeRes = await http.post(
        Uri.parse('$base/auth/pair/complete'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'pairRequestId': requestId}),
      );
      expect(completeRes.statusCode, 404);
    });

    test('brute force lockout after max attempts', () async {
      server.pairing.generateSecret();
      for (var i = 0; i < 5; i++) {
        await http.post(
          Uri.parse('$base/auth/pair/request'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'deviceName': 'Attacker',
            'devicePublicKey': '',
            'pairingSecret': '000000',
          }),
        );
      }
      final res = await http.post(
        Uri.parse('$base/auth/pair/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'deviceName': 'Attacker',
          'devicePublicKey': '',
          'pairingSecret': '000000',
        }),
      );
      expect(res.statusCode, 429);
    });
  });
}
