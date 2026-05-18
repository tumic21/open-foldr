import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:open_foldr/core/trusted_client_store.dart';
import 'package:open_foldr/server/server.dart';

void main() {
  late OpenFoldrServer server;
  const port = 17442;
  const base = 'http://127.0.0.1:$port/v1';

  setUpAll(() async {
    await TrustedClientStore.clear();
    server = OpenFoldrServer(port: port);
    await server.start();
  });

  tearDownAll(() => server.stop());

  setUp(() async {
    // Reset trusted store before each test.
    await TrustedClientStore.clear();
  });

  group('Trusted client auto-approve', () {
    Future<Map<String, dynamic>> _fullPair({
      required String deviceName,
      String fingerprint = '',
      String? deviceId,
    }) async {
      final secret = server.pairing.generateSecret();
      final reqBody = <String, dynamic>{
        'deviceName': deviceName,
        'devicePublicKey': fingerprint,
        'pairingSecret': secret,
        if (deviceId != null) 'deviceId': deviceId,
      };
      final reqRes = await http.post(
        Uri.parse('$base/auth/pair/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode(reqBody),
      );
      expect(reqRes.statusCode, 200, reason: 'pair/request failed');
      final requestId = (jsonDecode(reqRes.body))['pairRequestId'] as String;

      final completeRes = await http.post(
        Uri.parse('$base/auth/pair/complete'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'pairRequestId': requestId}),
      );
      expect(completeRes.statusCode, 200, reason: 'pair/complete failed');
      return jsonDecode(completeRes.body) as Map<String, dynamic>;
    }

    test('pairComplete response includes deviceId', () async {
      final body = await _fullPair(deviceName: 'Laptop');
      expect(body['deviceId'], isA<String>());
      expect((body['deviceId'] as String).isNotEmpty, isTrue);
    });

    test('reconnect via deviceToken works without pairing secret', () async {
      final body = await _fullPair(deviceName: 'Tablet');
      final deviceToken = body['deviceToken'] as String;

      final refreshRes = await http.post(
        Uri.parse('$base/auth/token/refresh'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'deviceToken': deviceToken}),
      );
      expect(refreshRes.statusCode, 200);
      final refreshBody = jsonDecode(refreshRes.body) as Map<String, dynamic>;
      expect(refreshBody['sessionToken'], isA<String>());
    });

    test('auto-approve: known deviceId skips pairing secret', () async {
      // First pairing to register the device.
      final first = await _fullPair(
        deviceName: 'Phone',
        fingerprint: 'fp-phone-1',
      );
      final deviceId = first['deviceId'] as String;

      // Simulate TrustedClientStore having persisted this device.
      await TrustedClientStore.upsert(
        TrustedClient(
          deviceId: deviceId,
          deviceName: 'Phone',
          publicKeyFingerprint: 'fp-phone-1',
          pairedAt: DateTime.now(),
        ),
      );

      // Second pair/request WITHOUT a valid secret but WITH the known deviceId.
      final reqRes = await http.post(
        Uri.parse('$base/auth/pair/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'deviceName': 'Phone',
          'devicePublicKey': 'fp-phone-1',
          'deviceId': deviceId,
          // No pairingSecret.
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
      final body = jsonDecode(completeRes.body) as Map<String, dynamic>;
      // Should get the same deviceId back.
      expect(body['deviceId'], deviceId);
    });

    test('auto-approve: known fingerprint skips pairing secret', () async {
      const fingerprint = 'fp-tablet-auto';

      // First full pair to establish the trust record.
      final first = await _fullPair(
        deviceName: 'Tablet',
        fingerprint: fingerprint,
      );
      final deviceId = first['deviceId'] as String;
      await TrustedClientStore.upsert(
        TrustedClient(
          deviceId: deviceId,
          deviceName: 'Tablet',
          publicKeyFingerprint: fingerprint,
          pairedAt: DateTime.now(),
        ),
      );

      // Reconnect using only fingerprint (no secret, no deviceId).
      final reqRes = await http.post(
        Uri.parse('$base/auth/pair/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'deviceName': 'Tablet',
          'devicePublicKey': fingerprint,
        }),
      );
      expect(reqRes.statusCode, 200);
    });

    test('unknown device without pairingSecret is rejected', () async {
      final reqRes = await http.post(
        Uri.parse('$base/auth/pair/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'deviceName': 'Stranger',
          'devicePublicKey': 'fp-unknown',
          // No pairingSecret.
        }),
      );
      expect(reqRes.statusCode, 400);
    });
  });
}
