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
  });
}
