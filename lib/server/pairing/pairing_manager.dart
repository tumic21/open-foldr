import 'dart:math';
import '../../core/constants.dart';

/// Generates and validates one-time pairing secrets with expiry and lockout.
class PairingManager {
  final _random = Random.secure();

  String? _currentSecret;
  DateTime? _secretExpiry;
  final Map<String, _AttemptRecord> _attemptsByIp = {};

  /// Generates a new numeric pairing secret. Invalidates any previous secret.
  String generateSecret() {
    final digits = List.generate(
      AppConstants.pairingSecretLength,
      (_) => _random.nextInt(10),
    );
    _currentSecret = digits.join();
    _secretExpiry = DateTime.now().add(
      const Duration(seconds: AppConstants.pairingSecretExpirySeconds),
    );
    return _currentSecret!;
  }

  /// Invalidates the current secret immediately.
  void invalidateSecret() {
    _currentSecret = null;
    _secretExpiry = null;
  }

  /// Returns true if [ip] is currently locked out.
  bool isLockedOut(String ip) {
    final record = _attemptsByIp[ip];
    if (record == null) return false;
    if (record.lockedUntil != null &&
        DateTime.now().isBefore(record.lockedUntil!)) {
      return true;
    }
    // Clear expired lockout.
    if (record.lockedUntil != null) _attemptsByIp.remove(ip);
    return false;
  }

  /// Validates the submitted [secret] for [ip].
  /// Returns null on success, or an error string on failure.
  String? validate(String ip, String secret) {
    if (isLockedOut(ip)) return 'RATE_LIMITED';

    if (_currentSecret == null || _secretExpiry == null) {
      return 'NO_ACTIVE_SECRET';
    }

    if (DateTime.now().isAfter(_secretExpiry!)) {
      invalidateSecret();
      return 'SECRET_EXPIRED';
    }

    final record = _attemptsByIp.putIfAbsent(ip, () => _AttemptRecord());

    if (secret != _currentSecret) {
      record.count++;
      if (record.count >= AppConstants.pairingMaxAttempts) {
        record.lockedUntil = DateTime.now().add(
          Duration(minutes: AppConstants.pairingLockoutMinutes),
        );
      }
      return 'INVALID_SECRET';
    }

    // Success: consume secret and clear attempt record.
    _attemptsByIp.remove(ip);
    invalidateSecret();
    return null;
  }
}

class _AttemptRecord {
  int count = 0;
  DateTime? lockedUntil;
}
