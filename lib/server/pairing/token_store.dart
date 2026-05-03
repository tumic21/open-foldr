import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants.dart';
import '../../models/role.dart';
import '../../models/device.dart';

/// Issues, validates, and revokes session tokens.
class TokenStore {
  final _uuid = const Uuid();
  final Map<String, _TokenRecord> _sessions = {};
  final Map<String, _DeviceRecord> _devices = {};

  /// Issues a session token and device token for a newly approved device.
  ({String sessionToken, String deviceToken, DateTime expiresAt}) issue({
    required String deviceId,
    required String deviceName,
    required String publicKeyFingerprint,
    required Role role,
  }) {
    final sessionToken = _uuid.v4();
    final deviceToken = _uuid.v4();
    final expiresAt = DateTime.now().add(
      Duration(minutes: AppConstants.sessionTokenTtlMinutes),
    );

    _sessions[_hash(sessionToken)] = _TokenRecord(
      deviceId: deviceId,
      role: role,
      expiresAt: expiresAt,
    );

    _devices[_hash(deviceToken)] = _DeviceRecord(
      deviceId: deviceId,
      deviceName: deviceName,
      publicKeyFingerprint: publicKeyFingerprint,
      role: role,
    );

    return (
      sessionToken: sessionToken,
      deviceToken: deviceToken,
      expiresAt: expiresAt,
    );
  }

  /// Validates a session token. Returns the [Role] if valid, null otherwise.
  Role? validate(String sessionToken) {
    final record = _sessions[_hash(sessionToken)];
    if (record == null) return null;
    if (DateTime.now().isAfter(record.expiresAt)) {
      _sessions.remove(_hash(sessionToken));
      return null;
    }
    return record.role;
  }

  /// Refreshes a session using a device token.
  /// Returns null if the device token is invalid.
  ({String sessionToken, DateTime expiresAt})? refresh(String deviceToken) {
    final record = _devices[_hash(deviceToken)];
    if (record == null) return null;

    final sessionToken = _uuid.v4();
    final expiresAt = DateTime.now().add(
      Duration(minutes: AppConstants.sessionTokenTtlMinutes),
    );

    _sessions[_hash(sessionToken)] = _TokenRecord(
      deviceId: record.deviceId,
      role: record.role,
      expiresAt: expiresAt,
    );

    return (sessionToken: sessionToken, expiresAt: expiresAt);
  }

  /// Revokes all tokens for a device.
  void revokeDevice(String deviceId) {
    _sessions.removeWhere((_, r) => r.deviceId == deviceId);
    _devices.removeWhere((_, r) => r.deviceId == deviceId);
  }

  /// Returns all currently registered devices.
  List<PairedDevice> get devices => _devices.values
      .map(
        (r) => PairedDevice(
          id: r.deviceId,
          name: r.deviceName,
          publicKeyFingerprint: r.publicKeyFingerprint,
          role: r.role,
          pairedAt: DateTime.now(),
        ),
      )
      .toList();

  String _hash(String token) =>
      sha256.convert(utf8.encode(token)).toString();
}

class _TokenRecord {
  final String deviceId;
  final Role role;
  final DateTime expiresAt;
  _TokenRecord({
    required this.deviceId,
    required this.role,
    required this.expiresAt,
  });
}

class _DeviceRecord {
  final String deviceId;
  final String deviceName;
  final String publicKeyFingerprint;
  final Role role;
  _DeviceRecord({
    required this.deviceId,
    required this.deviceName,
    required this.publicKeyFingerprint,
    required this.role,
  });
}
