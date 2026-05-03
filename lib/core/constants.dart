/// App-wide constants.
class AppConstants {
  AppConstants._();

  // mDNS service type for OpenFoldr hosts.
  static const String mdnsServiceType = '_openfoldr._tcp';

  // Default port the embedded shelf server binds to.
  static const int defaultPort = 7432;

  // Pairing secret length (digits).
  static const int pairingSecretLength = 6;

  // Pairing secret expiry in seconds.
  static const int pairingSecretExpirySeconds = 120;

  // Max failed pairing attempts before lockout.
  static const int pairingMaxAttempts = 5;

  // Lockout duration in minutes after max failed attempts.
  static const int pairingLockoutMinutes = 10;

  // Session token TTL in minutes.
  static const int sessionTokenTtlMinutes = 15;

  // Default activity log retention in days.
  static const int logRetentionDays = 14;

  // Max chunk size for resumable uploads (4 MiB).
  static const int maxChunkBytes = 4 * 1024 * 1024;

  // Max concurrent transfers per client.
  static const int maxConcurrentTransfers = 4;

  // Max non-resumable request body (64 MiB).
  static const int maxBodyBytes = 64 * 1024 * 1024;
}
