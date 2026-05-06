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
  /// Also updates the last-seen timestamp for the owning device.
  Role? validate(String sessionToken) {
    final hash = _hash(sessionToken);
    final record = _sessions[hash];
    if (record == null) return null;
    if (DateTime.now().isAfter(record.expiresAt)) {
      _sessions.remove(hash);
      return null;
    }
    // Mark the owning device as recently active.
    for (final d in _devices.values) {
      if (d.deviceId == record.deviceId) {
        d.lastSeenAt = DateTime.now();
        break;
      }
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

  /// Returns devices that have been seen within [threshold].
  /// Used to show "currently connected" devices on the host screen.
  List<PairedDevice> connectedDevices({
    Duration threshold = const Duration(seconds: 10),
  }) {
    final cutoff = DateTime.now().subtract(threshold);
    return _devices.values
        .where((r) => r.lastSeenAt != null && r.lastSeenAt!.isAfter(cutoff))
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
  }

  void syncAllRoles(Role role) {
    for (final session in _sessions.values) {
      session.role = role;
    }
    for (final device in _devices.values) {
      device.role = role;
    }
  }

  String _hash(String token) =>
      sha256.convert(utf8.encode(token)).toString();
}

class _TokenRecord {
  final String deviceId;
  Role role;
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
  Role role;
  DateTime? lastSeenAt;
  _DeviceRecord({
    required this.deviceId,
    required this.deviceName,
    required this.publicKeyFingerprint,
    required this.role,
  });
}
