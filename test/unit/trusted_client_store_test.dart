import 'package:flutter_test/flutter_test.dart';
import 'package:open_foldr/core/trusted_client_store.dart';
import 'package:open_foldr/models/role.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TrustedClientStore', () {
    TrustedClient _makeClient({
      String deviceId = 'device-1',
      String deviceName = 'Phone',
      String fingerprint = 'fp-001',
      Role role = Role.viewer,
    }) => TrustedClient(
      deviceId: deviceId,
      deviceName: deviceName,
      publicKeyFingerprint: fingerprint,
      role: role,
      pairedAt: DateTime.utc(2024, 1, 1),
    );

    test('load returns empty list initially', () async {
      final clients = await TrustedClientStore.load();
      expect(clients, isEmpty);
    });

    test('upsert and load round-trips a client', () async {
      final client = _makeClient();
      await TrustedClientStore.upsert(client);

      final loaded = await TrustedClientStore.load();
      expect(loaded.length, 1);
      expect(loaded.first.deviceId, client.deviceId);
      expect(loaded.first.deviceName, client.deviceName);
      expect(loaded.first.role, client.role);
    });

    test('upsert updates existing client by deviceId', () async {
      final original = _makeClient(deviceName: 'Phone v1', role: Role.viewer);
      await TrustedClientStore.upsert(original);

      final updated = _makeClient(deviceName: 'Phone v2', role: Role.editor);
      await TrustedClientStore.upsert(updated);

      final loaded = await TrustedClientStore.load();
      expect(loaded.length, 1);
      expect(loaded.first.deviceName, 'Phone v2');
      expect(loaded.first.role, Role.editor);
    });

    test('remove deletes a client by deviceId', () async {
      await TrustedClientStore.upsert(_makeClient(deviceId: 'dev-a'));
      await TrustedClientStore.upsert(
        _makeClient(deviceId: 'dev-b', fingerprint: 'fp-002'),
      );

      await TrustedClientStore.remove('dev-a');

      final loaded = await TrustedClientStore.load();
      expect(loaded.length, 1);
      expect(loaded.first.deviceId, 'dev-b');
    });

    test('findById returns matching client', () async {
      await TrustedClientStore.upsert(_makeClient(deviceId: 'dev-x'));
      final found = await TrustedClientStore.findById('dev-x');
      expect(found, isNotNull);
      expect(found!.deviceId, 'dev-x');
    });

    test('findById returns null for unknown id', () async {
      final found = await TrustedClientStore.findById('nobody');
      expect(found, isNull);
    });

    test('findByFingerprint returns matching client', () async {
      await TrustedClientStore.upsert(_makeClient(fingerprint: 'fp-unique'));
      final found = await TrustedClientStore.findByFingerprint('fp-unique');
      expect(found, isNotNull);
      expect(found!.publicKeyFingerprint, 'fp-unique');
    });

    test('findByFingerprint returns null for unknown fingerprint', () async {
      final found = await TrustedClientStore.findByFingerprint('fp-ghost');
      expect(found, isNull);
    });

    test('multiple clients coexist', () async {
      for (var i = 1; i <= 3; i++) {
        await TrustedClientStore.upsert(
          _makeClient(deviceId: 'dev-$i', fingerprint: 'fp-$i'),
        );
      }
      final loaded = await TrustedClientStore.load();
      expect(loaded.length, 3);
    });
  });
}
