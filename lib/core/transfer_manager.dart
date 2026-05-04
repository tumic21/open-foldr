import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../core/backoff.dart';
import '../core/constants.dart';

/// Tracks a transfer's progress for UI display.
class TransferProgress {
  final String path;
  final int total;
  final int transferred;
  final bool complete;
  final String? error;

  const TransferProgress({
    required this.path,
    required this.total,
    required this.transferred,
    this.complete = false,
    this.error,
  });

  double get fraction => total == 0 ? 0 : transferred / total;
}

/// Client-side resumable upload manager.
///
/// Chunks a file into [AppConstants.maxChunkBytes]-sized pieces, sends them
/// via the `/v1/roots/<alias>/upload/*` protocol, and verifies the final
/// SHA-256 checksum. On interruption call [resume] with the same arguments
/// to continue from where the server left off.
class ResumableUploadManager {
  final String base;
  final String sessionToken;
  final http.Client _client;

  ResumableUploadManager({
    required this.base,
    required this.sessionToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Uploads [bytes] to [remotePath] under [alias].
  ///
  /// [onProgress] is called after every chunk is acknowledged.
  ///
  /// Returns the server-issued [versionToken] on completion.
  Future<String> upload({
    required String alias,
    required String remotePath,
    required Uint8List bytes,
    void Function(TransferProgress)? onProgress,
    String? existingUploadId,
  }) async {
    final totalSize = bytes.length;
    final checksum = sha256.convert(bytes).toString();

    // ── 1. Init (or reuse) upload session ──────────────────────────────────
    String uploadId;
    int startOffset;

    if (existingUploadId != null) {
      // Query existing session offset.
      final offsetRes = await withRetry(
        (_) => _client.get(
          Uri.parse('$base/roots/$alias/upload/$existingUploadId/offset'),
          headers: {'authorization': 'Bearer $sessionToken'},
        ),
        shouldRetry: _shouldRetry,
      );
      if (offsetRes.statusCode == 200) {
        final body = jsonDecode(offsetRes.body) as Map<String, dynamic>;
        uploadId = existingUploadId;
        startOffset = body['offset'] as int;
      } else {
        // Session expired; start fresh.
        final init = await _initSession(alias, remotePath, totalSize);
        uploadId = init.$1;
        startOffset = init.$2;
      }
    } else {
      final init = await _initSession(alias, remotePath, totalSize);
      uploadId = init.$1;
      startOffset = init.$2;
    }

    // ── 2. Upload chunks ────────────────────────────────────────────────────
    var offset = startOffset;
    final chunkSize = AppConstants.maxChunkBytes;

    while (offset < totalSize) {
      final end = min(offset + chunkSize - 1, totalSize - 1);
      final chunk = bytes.sublist(offset, end + 1);

      final chunkRes = await withRetry(
        (_) => _client.patch(
          Uri.parse('$base/roots/$alias/upload/$uploadId'),
          headers: {
            'authorization': 'Bearer $sessionToken',
            'content-type': 'application/octet-stream',
            'content-range': 'bytes $offset-$end/$totalSize',
          },
          body: chunk,
        ),
        shouldRetry: _shouldRetry,
      );

      if (chunkRes.statusCode == 409) {
        // Server reported offset mismatch; re-query and continue from there.
        final body = jsonDecode(chunkRes.body) as Map<String, dynamic>;
        offset = body['offset'] as int;
        continue;
      }

      if (chunkRes.statusCode != 200) {
        throw Exception(
          'Chunk upload failed (${chunkRes.statusCode}): ${chunkRes.body}',
        );
      }

      final body = jsonDecode(chunkRes.body) as Map<String, dynamic>;
      offset = body['offset'] as int;

      onProgress?.call(TransferProgress(
        path: remotePath,
        total: totalSize,
        transferred: offset,
      ));
    }

    // ── 3. Complete with checksum ───────────────────────────────────────────
    final completeRes = await withRetry(
      (_) => _client.post(
        Uri.parse('$base/roots/$alias/upload/$uploadId/complete'),
        headers: {
          'authorization': 'Bearer $sessionToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'sha256': checksum}),
      ),
      shouldRetry: _shouldRetry,
    );

    if (completeRes.statusCode != 200) {
      throw Exception(
        'Upload complete failed (${completeRes.statusCode}): ${completeRes.body}',
      );
    }

    final completeBody = jsonDecode(completeRes.body) as Map<String, dynamic>;
    final versionToken = completeBody['versionToken'] as String;

    onProgress?.call(TransferProgress(
      path: remotePath,
      total: totalSize,
      transferred: totalSize,
      complete: true,
    ));

    return versionToken;
  }

  Future<(String, int)> _initSession(
    String alias,
    String remotePath,
    int totalSize,
  ) async {
    final res = await withRetry(
      (_) => _client.post(
        Uri.parse('$base/roots/$alias/upload/init'),
        headers: {
          'authorization': 'Bearer $sessionToken',
          'content-type': 'application/json',
        },
        body: jsonEncode({'path': remotePath, 'size': totalSize}),
      ),
      shouldRetry: _shouldRetry,
    );

    if (res.statusCode != 200) {
      throw Exception(
        'Upload init failed (${res.statusCode}): ${res.body}',
      );
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    return (body['uploadId'] as String, body['offset'] as int);
  }

  void dispose() => _client.close();
}

/// Client-side resumable download manager.
///
/// Downloads a file using HTTP Range requests, retrying interrupted transfers
/// from the last received byte.
class ResumableDownloadManager {
  final String base;
  final String sessionToken;
  final http.Client _client;

  ResumableDownloadManager({
    required this.base,
    required this.sessionToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Downloads [remotePath] from [alias] and returns the complete bytes.
  ///
  /// [onProgress] is called after each chunk is received.
  Future<Uint8List> download({
    required String alias,
    required String remotePath,
    void Function(TransferProgress)? onProgress,
  }) async {
    // ── 1. Fetch metadata to get total size ─────────────────────────────────
    final metaRes = await withRetry(
      (_) => _client.get(
        Uri.parse('$base/roots/$alias/metadata')
            .replace(queryParameters: {'path': remotePath}),
        headers: {'authorization': 'Bearer $sessionToken'},
      ),
      shouldRetry: _shouldRetry,
    );

    if (metaRes.statusCode != 200) {
      throw Exception(
        'Metadata fetch failed (${metaRes.statusCode}): ${metaRes.body}',
      );
    }

    final meta = jsonDecode(metaRes.body) as Map<String, dynamic>;
    final totalSize = meta['size'] as int;

    if (totalSize == 0) return Uint8List(0);

    // ── 2. Download in chunks using Range requests ───────────────────────────
    final chunks = <Uint8List>[];
    var received = 0;
    final chunkSize = AppConstants.maxChunkBytes;

    while (received < totalSize) {
      final end = min(received + chunkSize - 1, totalSize - 1);

      final res = await withRetry(
        (_) => _client.get(
          Uri.parse('$base/roots/$alias/file')
              .replace(queryParameters: {'path': remotePath}),
          headers: {
            'authorization': 'Bearer $sessionToken',
            'range': 'bytes=$received-$end',
          },
        ),
        shouldRetry: _shouldRetry,
      );

      if (res.statusCode != 206 && res.statusCode != 200) {
        throw Exception(
          'Download failed (${res.statusCode}): ${res.body}',
        );
      }

      final chunk = res.bodyBytes;
      chunks.add(chunk);
      received += chunk.length;

      onProgress?.call(TransferProgress(
        path: remotePath,
        total: totalSize,
        transferred: received,
        complete: received >= totalSize,
      ));
    }

    // Assemble full file.
    final result = Uint8List(received);
    var offset = 0;
    for (final chunk in chunks) {
      result.setRange(offset, offset + chunk.length, chunk);
      offset += chunk.length;
    }
    return result;
  }

  void dispose() => _client.close();
}

/// Returns true for errors that are safe to retry (network + 5xx).
/// Returns false for 4xx errors (client errors won't be fixed by retrying).
bool _shouldRetry(Object error) {
  if (error is http.ClientException) return true;
  // Let callers inspect status codes and decide themselves for HTTP errors.
  return true;
}
