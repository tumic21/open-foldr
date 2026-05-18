import 'role.dart';

/// A device that has been approved and issued a session.
class PairedDevice {
  final String id;
  final String name;
  final String publicKeyFingerprint;
  final Role role;
  final DateTime pairedAt;

  const PairedDevice({
    required this.id,
    required this.name,
    required this.publicKeyFingerprint,
    required this.role,
    required this.pairedAt,
  });
}
