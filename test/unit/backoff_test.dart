import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_foldr/core/backoff.dart';

void main() {
  group('backoffDelay', () {
    test('attempt 0 produces delay in [0, base] range', () {
      // With a fixed seed we can assert the jitter range.
      for (var i = 0; i < 100; i++) {
        final d = backoffDelay(attempt: 0, baseMs: 200);
        expect(d.inMilliseconds, greaterThanOrEqualTo(0));
        expect(d.inMilliseconds, lessThanOrEqualTo(200));
      }
    });

    test('delay is capped at capMs before jitter', () {
      for (var i = 0; i < 50; i++) {
        final d = backoffDelay(attempt: 20, baseMs: 200, capMs: 1000);
        expect(d.inMilliseconds, lessThanOrEqualTo(1000));
      }
    });

    test('delay grows with attempt number (statistically)', () {
      // With deterministic rng seeded with 1, higher attempts → larger delays.
      final rng = Random(1);
      final d0 = backoffDelay(attempt: 0, baseMs: 200, capMs: 30000, rng: rng);
      final rng2 = Random(1);
      final d5 = backoffDelay(attempt: 5, baseMs: 200, capMs: 30000, rng: rng2);
      // Not guaranteed for every seed but true for seed=1.
      expect(d5.inMilliseconds, greaterThanOrEqualTo(d0.inMilliseconds));
    });
  });

  group('withRetry', () {
    test('succeeds on first attempt with no retries', () async {
      var calls = 0;
      final result = await withRetry((_) async {
        calls++;
        return 42;
      });
      expect(result, 42);
      expect(calls, 1);
    });

    test('retries on failure and eventually succeeds', () async {
      var calls = 0;
      final result = await withRetry(
        (attempt) async {
          calls++;
          if (attempt < 2) throw Exception('transient');
          return 'ok';
        },
        maxAttempts: 5,
        baseMs: 1, // tiny delay for tests
      );
      expect(result, 'ok');
      expect(calls, 3);
    });

    test('throws after maxAttempts exhausted', () async {
      var calls = 0;
      await expectLater(
        () => withRetry(
          (_) async {
            calls++;
            throw Exception('always fails');
          },
          maxAttempts: 3,
          baseMs: 1,
        ),
        throwsA(isA<Exception>()),
      );
      expect(calls, 3);
    });

    test('stops immediately when shouldRetry returns false', () async {
      var calls = 0;
      await expectLater(
        () => withRetry(
          (_) async {
            calls++;
            throw StateError('permanent');
          },
          maxAttempts: 5,
          baseMs: 1,
          shouldRetry: (e) => false,
        ),
        throwsA(isA<StateError>()),
      );
      expect(calls, 1);
    });
  });
}
