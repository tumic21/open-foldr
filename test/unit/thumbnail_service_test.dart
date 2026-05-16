import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:open_foldr/client/file_client.dart';
import 'package:open_foldr/core/result.dart';
import 'package:open_foldr/ui/services/thumbnail_service.dart';

class _FakeFileClient extends FileClient {
  final Future<Result<ThumbnailResponse>> Function({
    required String alias,
    required String path,
    required int width,
    required int height,
    required String fit,
    String? ifNoneMatch,
  })
  handler;

  _FakeFileClient(this.handler)
    : super(baseUrl: 'http://localhost/v1', sessionToken: 'tok');

  @override
  Future<Result<ThumbnailResponse>> getThumbnail(
    String alias,
    String path, {
    required int width,
    required int height,
    String fit = 'cover',
    String? ifNoneMatch,
  }) {
    return handler(
      alias: alias,
      path: path,
      width: width,
      height: height,
      fit: fit,
      ifNoneMatch: ifNoneMatch,
    );
  }
}

void main() {
  group('ThumbnailService', () {
    test('returns cached thumbnail on repeated request', () async {
      var calls = 0;
      final client = _FakeFileClient(({
        required alias,
        required path,
        required width,
        required height,
        required fit,
        String? ifNoneMatch,
      }) async {
        calls++;
        return Ok(
          ThumbnailResponse(
            bytes: Uint8List.fromList([1, 2, 3]),
            etag: 'etag-1',
            contentType: 'image/jpeg',
          ),
        );
      });
      final service = ThumbnailService(cacheBudgetBytes: 1024 * 1024);

      final first = await service.getThumbnail(
        client: client,
        alias: 'docs',
        path: '/image.jpg',
        width: 48,
        height: 48,
      );
      final second = await service.getThumbnail(
        client: client,
        alias: 'docs',
        path: '/image.jpg',
        width: 48,
        height: 48,
      );

      expect(first.isOk, isTrue);
      expect(second.isOk, isTrue);
      expect(second.unwrap.bytes, isNotNull);
      expect(calls, 1);
    });

    test('coalesces concurrent requests for the same key', () async {
      var calls = 0;
      final completer = Completer<Result<ThumbnailResponse>>();
      final client = _FakeFileClient(({
        required alias,
        required path,
        required width,
        required height,
        required fit,
        String? ifNoneMatch,
      }) {
        calls++;
        return completer.future;
      });

      final service = ThumbnailService(cacheBudgetBytes: 1024 * 1024);

      final f1 = service.getThumbnail(
        client: client,
        alias: 'docs',
        path: '/same.jpg',
        width: 48,
        height: 48,
      );
      final f2 = service.getThumbnail(
        client: client,
        alias: 'docs',
        path: '/same.jpg',
        width: 48,
        height: 48,
      );

      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);

      completer.complete(
        Ok(
          ThumbnailResponse(
            bytes: Uint8List.fromList([9, 9, 9]),
            etag: 'etag-same',
            contentType: 'image/jpeg',
          ),
        ),
      );

      final results = await Future.wait([f1, f2]);
      expect(results[0].isOk, isTrue);
      expect(results[1].isOk, isTrue);
      expect(calls, 1);
    });

    test('respects maxInFlight concurrency limit', () async {
      var active = 0;
      var peak = 0;

      final client = _FakeFileClient(({
        required alias,
        required path,
        required width,
        required height,
        required fit,
        String? ifNoneMatch,
      }) async {
        active++;
        if (active > peak) peak = active;
        await Future<void>.delayed(const Duration(milliseconds: 30));
        active--;
        return Ok(
          ThumbnailResponse(
            bytes: Uint8List.fromList([7]),
            etag: path,
            contentType: 'image/jpeg',
          ),
        );
      });

      final service = ThumbnailService(
        cacheBudgetBytes: 1024 * 1024,
        maxInFlight: 2,
      );

      await Future.wait(
        List.generate(6, (i) {
          return service.getThumbnail(
            client: client,
            alias: 'docs',
            path: '/$i.jpg',
            width: 128,
            height: 128,
          );
        }),
      );

      expect(peak, lessThanOrEqualTo(2));
    });

    test('evicts oldest entries when cache budget is exceeded', () async {
      var calls = 0;
      final client = _FakeFileClient(({
        required alias,
        required path,
        required width,
        required height,
        required fit,
        String? ifNoneMatch,
      }) async {
        calls++;
        return Ok(
          ThumbnailResponse(
            bytes: Uint8List.fromList(List.filled(10, calls)),
            etag: '$calls',
            contentType: 'image/jpeg',
          ),
        );
      });

      final service = ThumbnailService(
        cacheBudgetBytes: 20,
        enableDebugLogs: false,
      );

      await service.getThumbnail(
        client: client,
        alias: 'docs',
        path: '/a.jpg',
        width: 48,
        height: 48,
      );
      await service.getThumbnail(
        client: client,
        alias: 'docs',
        path: '/b.jpg',
        width: 48,
        height: 48,
      );
      await service.getThumbnail(
        client: client,
        alias: 'docs',
        path: '/c.jpg',
        width: 48,
        height: 48,
      );

      expect(service.cacheBytes, lessThanOrEqualTo(service.cacheBudgetBytes));
      expect(service.cacheItems, lessThanOrEqualTo(2));

      await service.getThumbnail(
        client: client,
        alias: 'docs',
        path: '/a.jpg',
        width: 48,
        height: 48,
      );
      expect(calls, 4, reason: 'Oldest cached entry should have been evicted.');
    });

    test(
      'collects metrics for synthetic 100/500/2000 directory workloads',
      () async {
        final sizes = [100, 500, 2000];

        for (final count in sizes) {
          var active = 0;
          var peak = 0;
          var calls = 0;

          final client = _FakeFileClient(({
            required alias,
            required path,
            required width,
            required height,
            required fit,
            String? ifNoneMatch,
          }) async {
            calls++;
            active++;
            if (active > peak) peak = active;
            await Future<void>.delayed(const Duration(milliseconds: 1));
            active--;
            return Ok(
              ThumbnailResponse(
                bytes: Uint8List.fromList(List.filled(64, 1)),
                etag: path,
                contentType: 'image/jpeg',
              ),
            );
          });

          final service = ThumbnailService(
            cacheBudgetBytes: 1024 * 1024,
            maxInFlight: 4,
            enableDebugLogs: false,
          );

          await Future.wait(
            List.generate(count, (i) {
              return service.getThumbnail(
                client: client,
                alias: 'docs',
                path: '/cold-$i.jpg',
                width: 128,
                height: 128,
              );
            }),
          );
          final callsAfterCold = calls;

          await Future.wait(
            List.generate(count, (i) {
              return service.getThumbnail(
                client: client,
                alias: 'docs',
                path: '/cold-$i.jpg',
                width: 128,
                height: 128,
              );
            }),
          );

          final m = service.metricsSnapshot;
          expect(callsAfterCold, count);
          expect(
            calls,
            count,
            reason: 'Warm pass should be served from cache.',
          );
          expect(m.requests, count * 2);
          expect(m.cacheHits, count);
          expect(m.cacheMisses, count);
          expect(m.networkSuccesses, count);
          expect(m.networkErrors, 0);
          expect(m.hitRate, closeTo(0.5, 0.001));
          expect(m.averageFetchMs, greaterThan(0));
          expect(peak, lessThanOrEqualTo(4));
          expect(
            service.cacheBytes,
            lessThanOrEqualTo(service.cacheBudgetBytes),
          );
        }
      },
    );

    test('tracks decode failures in metrics', () {
      final service = ThumbnailService(enableDebugLogs: false);
      expect(service.metricsSnapshot.decodeFailures, 0);
      service.reportDecodeFailure();
      service.reportDecodeFailure();
      expect(service.metricsSnapshot.decodeFailures, 2);
    });

    test('cancelThumbnail skips network call for queued request', () async {
      var calls = 0;
      // Use a slow first request to hold the single permit, forcing the second
      // into the waiters queue where it can be cancelled.
      final firstCompleter = Completer<Result<ThumbnailResponse>>();
      final client = _FakeFileClient(({
        required alias,
        required path,
        required width,
        required height,
        required fit,
        String? ifNoneMatch,
      }) {
        calls++;
        if (path == '/slow.jpg') return firstCompleter.future;
        return Future.value(
          Ok(
            ThumbnailResponse(
              bytes: Uint8List.fromList([2]),
              etag: 'e2',
              contentType: 'image/jpeg',
            ),
          ),
        );
      });

      final service = ThumbnailService(
        cacheBudgetBytes: 1024 * 1024,
        maxInFlight: 1,
        enableDebugLogs: false,
      );

      // Fill the single permit slot.
      final f1 = service.getThumbnail(
        client: client,
        alias: 'docs',
        path: '/slow.jpg',
        width: 48,
        height: 48,
      );

      // Yield so the first request acquires the permit.
      await Future<void>.delayed(Duration.zero);

      // Queue a second request (still waiting for the permit).
      final f2 = service.getThumbnail(
        client: client,
        alias: 'docs',
        path: '/queued.jpg',
        width: 48,
        height: 48,
      );

      // Cancel the queued request before the permit is released.
      service.cancelThumbnail(
        alias: 'docs',
        path: '/queued.jpg',
        width: 48,
        height: 48,
      );

      // Release the first permit.
      firstCompleter.complete(
        Ok(
          ThumbnailResponse(
            bytes: Uint8List.fromList([1]),
            etag: 'e1',
            contentType: 'image/jpeg',
          ),
        ),
      );

      await f1;
      final result2 = await f2;

      expect(calls, 1, reason: 'Only the first (non-cancelled) request should reach the network.');
      expect(result2.isErr, isTrue);
      expect(result2.errorCode, 'CANCELLED');
    });

    test('cancelThumbnail allows re-request after cancellation', () async {
      var calls = 0;
      final client = _FakeFileClient(({
        required alias,
        required path,
        required width,
        required height,
        required fit,
        String? ifNoneMatch,
      }) async {
        calls++;
        return Ok(
          ThumbnailResponse(
            bytes: Uint8List.fromList([1]),
            etag: 'e',
            contentType: 'image/jpeg',
          ),
        );
      });

      final service = ThumbnailService(
        cacheBudgetBytes: 1024 * 1024,
        enableDebugLogs: false,
      );

      // Cancel a key that was never requested — should be a no-op.
      service.cancelThumbnail(
        alias: 'docs',
        path: '/img.jpg',
        width: 48,
        height: 48,
      );

      // A fresh request after cancellation should succeed.
      final result = await service.getThumbnail(
        client: client,
        alias: 'docs',
        path: '/img.jpg',
        width: 48,
        height: 48,
      );

      expect(calls, 1);
      expect(result.isOk, isTrue);
    });
  });
}
