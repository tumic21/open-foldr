import 'dart:math';

/// Computes exponential backoff delay with full jitter.
///
/// Formula: `min(capMs, baseMs * 2^attempt) * random(0, 1)`
///
/// [attempt] is 0-based (first retry is attempt 0).
/// [baseMs]  is the base delay in milliseconds (default 200 ms).
/// [capMs]   is the maximum delay before jitter in milliseconds (default 30 s).
Duration backoffDelay({
  required int attempt,
  int baseMs = 200,
  int capMs = 30000,
  Random? rng,
}) {
  final random = rng ?? Random();
  final exponential = baseMs * pow(2, attempt).toInt();
  final capped = min(exponential, capMs);
  final jittered = (capped * random.nextDouble()).round();
  return Duration(milliseconds: jittered);
}

/// Retries [fn] up to [maxAttempts] times using exponential backoff + jitter.
///
/// Calls [fn] with the current attempt number (0-based).
/// Returns the result of the first successful call.
/// Re-throws the last exception if all attempts are exhausted.
/// If [shouldRetry] is provided it is called with the exception; returning
/// false stops retrying immediately (e.g. for 4xx errors that won't recover).
Future<T> withRetry<T>(
  Future<T> Function(int attempt) fn, {
  int maxAttempts = 5,
  int baseMs = 200,
  int capMs = 30000,
  bool Function(Object error)? shouldRetry,
  Random? rng,
}) async {
  Object lastError = Exception('No attempts made');
  for (var i = 0; i < maxAttempts; i++) {
    try {
      return await fn(i);
    } catch (e) {
      lastError = e;
      if (shouldRetry != null && !shouldRetry(e)) rethrow;
      if (i < maxAttempts - 1) {
        await Future<void>.delayed(
          backoffDelay(attempt: i, baseMs: baseMs, capMs: capMs, rng: rng),
        );
      }
    }
  }
  throw lastError;
}
