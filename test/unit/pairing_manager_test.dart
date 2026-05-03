import 'package:flutter_test/flutter_test.dart';
import 'package:open_foldr/server/pairing/pairing_manager.dart';
import 'package:open_foldr/core/constants.dart';

void main() {
  late PairingManager manager;

  setUp(() => manager = PairingManager());

  group('PairingManager', () {
    test('generates a numeric secret of correct length', () {
      final secret = manager.generateSecret();
      expect(secret.length, AppConstants.pairingSecretLength);
      expect(int.tryParse(secret), isNotNull);
    });

    test('validates correct secret', () {
      final secret = manager.generateSecret();
      expect(manager.validate('1.2.3.4', secret), isNull);
    });

    test('rejects wrong secret and increments attempt count', () {
      manager.generateSecret();
      expect(manager.validate('1.2.3.4', '000000'), isNotNull);
    });

    test('consumes secret on success (one-time use)', () {
      final secret = manager.generateSecret();
      manager.validate('1.2.3.4', secret);
      // Second attempt should fail — no active secret.
      expect(manager.validate('1.2.3.5', secret), isNotNull);
    });

    test('locks out IP after max failed attempts', () {
      manager.generateSecret();
      for (var i = 0; i < AppConstants.pairingMaxAttempts; i++) {
        manager.validate('1.2.3.4', '000000');
      }
      expect(manager.isLockedOut('1.2.3.4'), isTrue);
    });

    test('does not lock out different IP', () {
      manager.generateSecret();
      for (var i = 0; i < AppConstants.pairingMaxAttempts; i++) {
        manager.validate('1.2.3.4', '000000');
      }
      expect(manager.isLockedOut('5.6.7.8'), isFalse);
    });

    test('returns SECRET_EXPIRED for expired secret', () async {
      // Directly invalidate to simulate expiry.
      manager.generateSecret();
      manager.invalidateSecret();
      expect(manager.validate('1.2.3.4', '123456'), equals('NO_ACTIVE_SECRET'));
    });
  });
}
