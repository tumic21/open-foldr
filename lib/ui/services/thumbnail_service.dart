import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../../client/file_client.dart';

typedef _CacheKey = String;

class ThumbnailService {
  ThumbnailService({
    int? cacheBudgetBytes,
    this.maxInFlight = 4,
    bool? enableDebugLogs,
    this.debugLogEvery = 200,
  }) : _cacheBudgetBytes = cacheBudgetBytes ?? _defaultCacheBudgetBytes(),
       enableDebugLogs = enableDebugLogs ?? kDebugMode;

  static final ThumbnailService instance = ThumbnailService();

  final int maxInFlight;
  final bool enableDebugLogs;
  final int debugLogEvery;
  final int _cacheBudgetBytes;

  final LinkedHashMap<_CacheKey, _CachedThumbnail> _cache = LinkedHashMap();
  final Map<_CacheKey, Future<Result<ThumbnailResponse>>> _inFlight = {};
  final Queue<Completer<void>> _waiters = Queue();

  int _cacheBytes = 0;
  int _activeRequests = 0;
  int _requests = 0;
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _coalescedRequests = 0;
  int _networkSuccesses = 0;
  int _networkErrors = 0;
  int _decodeFailures = 0;
  int _totalFetchMicros = 0;

  int get cacheBudgetBytes => _cacheBudgetBytes;
  int get cacheBytes => _cacheBytes;
  int get cacheItems => _cache.length;

  ThumbnailMetricsSnapshot get metricsSnapshot => ThumbnailMetricsSnapshot(
    requests: _requests,
    cacheHits: _cacheHits,
    cacheMisses: _cacheMisses,
    coalescedRequests: _coalescedRequests,
    networkSuccesses: _networkSuccesses,
    networkErrors: _networkErrors,
    decodeFailures: _decodeFailures,
    totalFetchMicros: _totalFetchMicros,
  );

  Future<Result<ThumbnailResponse>> getThumbnail({
    required FileClient client,
    required String alias,
    required String path,
    required int width,
    required int height,
    String fit = 'cover',
  }) async {
    _requests++;
    final w = width.clamp(24, 512);
    final h = height.clamp(24, 512);
    final key = _makeKey(alias, path, w, h, fit);

    final cached = _cache.remove(key);
    if (cached != null) {
      _cacheHits++;
      _cache[key] = cached;
      _maybeDebugLog();
      return Ok(
        ThumbnailResponse(
          bytes: cached.bytes,
          etag: cached.etag,
          contentType: cached.contentType,
        ),
      );
    }

    _cacheMisses++;

    final existing = _inFlight[key];
    if (existing != null) {
      _coalescedRequests++;
      _maybeDebugLog();
      return existing;
    }

    final future = _withPermit(() async {
      final stopwatch = Stopwatch()..start();
      final result = await client.getThumbnail(
        alias,
        path,
        width: w,
        height: h,
        fit: fit,
      );
      stopwatch.stop();
      _totalFetchMicros += stopwatch.elapsedMicroseconds;

      if (result.isOk) {
        _networkSuccesses++;
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
      } else {
        _networkErrors++;
      }
      _maybeDebugLog();
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

  void resetMetrics() {
    _requests = 0;
    _cacheHits = 0;
    _cacheMisses = 0;
    _coalescedRequests = 0;
    _networkSuccesses = 0;
    _networkErrors = 0;
    _decodeFailures = 0;
    _totalFetchMicros = 0;
  }

  void reportDecodeFailure() {
    _decodeFailures++;
    _maybeDebugLog(force: true);
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

  void _maybeDebugLog({bool force = false}) {
    if (!enableDebugLogs) return;
    if (!force && (_requests == 0 || _requests % debugLogEvery != 0)) return;
    final snapshot = metricsSnapshot;
    debugPrint(
      '[thumbnail] req=${snapshot.requests} '
      'hit=${snapshot.cacheHits} miss=${snapshot.cacheMisses} '
      'coalesced=${snapshot.coalescedRequests} '
      'net_ok=${snapshot.networkSuccesses} net_err=${snapshot.networkErrors} '
      'decode_err=${snapshot.decodeFailures} '
      'avg_fetch_ms=${snapshot.averageFetchMs.toStringAsFixed(1)} '
      'cache_items=$cacheItems cache_bytes=$cacheBytes',
    );
  }
}

class ThumbnailMetricsSnapshot {
  final int requests;
  final int cacheHits;
  final int cacheMisses;
  final int coalescedRequests;
  final int networkSuccesses;
  final int networkErrors;
  final int decodeFailures;
  final int totalFetchMicros;

  const ThumbnailMetricsSnapshot({
    required this.requests,
    required this.cacheHits,
    required this.cacheMisses,
    required this.coalescedRequests,
    required this.networkSuccesses,
    required this.networkErrors,
    required this.decodeFailures,
    required this.totalFetchMicros,
  });

  double get hitRate {
    final total = cacheHits + cacheMisses;
    if (total == 0) return 0;
    return cacheHits / total;
  }

  double get averageFetchMs {
    if (networkSuccesses + networkErrors == 0) return 0;
    final avgMicros = totalFetchMicros / (networkSuccesses + networkErrors);
    return avgMicros / 1000.0;
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
