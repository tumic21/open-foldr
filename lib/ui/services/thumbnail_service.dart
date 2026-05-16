import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../client/file_client.dart';

typedef _CacheKey = String;

class ThumbnailService {
  ThumbnailService({int? cacheBudgetBytes, this.maxInFlight = 4})
    : _cacheBudgetBytes = cacheBudgetBytes ?? _defaultCacheBudgetBytes();

  static final ThumbnailService instance = ThumbnailService();

  final int maxInFlight;
  final int _cacheBudgetBytes;

  final LinkedHashMap<_CacheKey, _CachedThumbnail> _cache = LinkedHashMap();
  final Map<_CacheKey, Future<Result<ThumbnailResponse>>> _inFlight = {};
  final Queue<Completer<void>> _waiters = Queue();

  int _cacheBytes = 0;
  int _activeRequests = 0;

  Future<Result<ThumbnailResponse>> getThumbnail({
    required FileClient client,
    required String alias,
    required String path,
    required int width,
    required int height,
    String fit = 'cover',
  }) async {
    final w = width.clamp(24, 512);
    final h = height.clamp(24, 512);
    final key = _makeKey(alias, path, w, h, fit);

    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return Ok(
        ThumbnailResponse(
          bytes: cached.bytes,
          etag: cached.etag,
          contentType: cached.contentType,
        ),
      );
    }

    final existing = _inFlight[key];
    if (existing != null) return existing;

    final future = _withPermit(() async {
      final result = await client.getThumbnail(
        alias,
        path,
        width: w,
        height: h,
        fit: fit,
      );

      if (result.isOk) {
        final thumbnail = result.unwrap;
        if (!thumbnail.notModified && thumbnail.bytes != null) {
          _store(
            key,
            _CachedThumbnail(
              bytes: thumbnail.bytes!,
              etag: thumbnail.etag,
              contentType: thumbnail.contentType,
            ),
          );
        }
      }
      return result;
    });

    _inFlight[key] = future;
    future.whenComplete(() {
      _inFlight.remove(key);
    });

    return future;
  }

  void clear() {
    _cache.clear();
    _cacheBytes = 0;
  }

  Future<T> _withPermit<T>(Future<T> Function() task) async {
    while (_activeRequests >= maxInFlight) {
      final waiter = Completer<void>();
      _waiters.addLast(waiter);
      await waiter.future;
    }

    _activeRequests++;
    try {
      return await task();
    } finally {
      _activeRequests--;
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      }
    }
  }

  void _store(_CacheKey key, _CachedThumbnail value) {
    final previous = _cache.remove(key);
    if (previous != null) {
      _cacheBytes -= previous.bytes.length;
    }

    _cache[key] = value;
    _cacheBytes += value.bytes.length;

    while (_cacheBytes > _cacheBudgetBytes && _cache.isNotEmpty) {
      final oldestKey = _cache.keys.first;
      final removed = _cache.remove(oldestKey);
      if (removed != null) {
        _cacheBytes -= removed.bytes.length;
      }
    }
  }

  static String _makeKey(
    String alias,
    String path,
    int width,
    int height,
    String fit,
  ) {
    return '$alias|$path|$width|$height|$fit';
  }

  static int _defaultCacheBudgetBytes() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        return 24 * 1024 * 1024;
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.fuchsia:
        return 64 * 1024 * 1024;
    }
  }
}

class _CachedThumbnail {
  final Uint8List bytes;
  final String? etag;
  final String contentType;

  const _CachedThumbnail({
    required this.bytes,
    required this.etag,
    required this.contentType,
  });
}
