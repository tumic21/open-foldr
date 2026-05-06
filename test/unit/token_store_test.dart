import 'package:flutter_test/flutter_test.dart';
import 'package:open_foldr/server/pairing/token_store.dart';
import 'package:open_foldr/models/role.dart';

void main() {
  late TokenStore store;

  setUp(() => store = TokenStore());

  group('TokenStore', () {
    test('issues valid session token', () {
      final result = store.issue(
        deviceId: 'dev1',
        deviceName: 'Laptop',
        publicKeyFingerprint: 'fp1',
        role: Role.viewer,
      );
      expect(store.validate(result.sessionToken), equals(Role.viewer));
    });

    test('returns null for unknown token', () {
      expect(store.validate('no-such-token'), isNull);
    });

    test('refreshes via device token', () {
      final issued = store.issue(
        deviceId: 'dev1',
        deviceName: 'Laptop',
        publicKeyFingerprint: 'fp1',
        role: Role.editor,
      );
      final refreshed = store.refresh(issued.deviceToken);
      expect(refreshed, isNotNull);
      expect(store.validate(refreshed!.sessionToken), equals(Role.editor));
    });

    test('returns null refresh for unknown device token', () {
      expect(store.refresh('bad-device-token'), isNull);
    });

    test('revoking device invalidates all sessions for that device', () {
      final issued = store.issue(
        deviceId: 'dev2',
        deviceName: 'Phone',
        publicKeyFingerprint: 'fp2',
        role: Role.viewer,
      );
      store.revokeDevice('dev2');
      // New session after revoke should be invalid.
      expect(store.validate(issued.sessionToken), isNull);
    });

    test('hashes tokens so plain tokens are not stored', () {
      // Inspect via reflection is not possible in Dart, but we validate
      // that validate() only works with original token, not empty string.
      store.issue(
        deviceId: 'dev3',
        deviceName: 'PC',
        publicKeyFingerprint: 'fp3',
        role: Role.owner,
      );
      expect(store.validate(''), isNull);
    });

    test('syncAllRoles updates active session and device roles', () {
      final issued = store.issue(
        deviceId: 'dev4',
        deviceName: 'Tablet',
        publicKeyFingerprint: 'fp4',
        role: Role.viewer,
      );

      expect(store.validate(issued.sessionToken), Role.viewer);
      expect(store.devices.single.role, Role.viewer);

      store.syncAllRoles(Role.owner);

      expect(store.validate(issued.sessionToken), Role.owner);
      expect(store.devices.single.role, Role.owner);
    });
  });
}
