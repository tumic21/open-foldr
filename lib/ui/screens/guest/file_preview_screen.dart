import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../core/transfer_manager.dart';

/// Supported preview types.
enum _PreviewKind { image, text, binary }

_PreviewKind _previewKind(String name) {
  final ext = name.contains('.')
      ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
      : '';

  const imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
  const textExts = {
    'txt', 'md', 'json', 'yaml', 'yml', 'toml', 'csv',
    'html', 'htm', 'xml', 'css', 'js', 'ts', 'dart', 'py',
    'sh', 'bat', 'log', 'ini', 'cfg', 'conf',
  };

  if (imageExts.contains(ext)) return _PreviewKind.image;
  if (textExts.contains(ext)) return _PreviewKind.text;
  return _PreviewKind.binary;
}

/// Full-screen file preview supporting images, text, and binary files.
///
/// Uses [ResumableDownloadManager] for download so large files benefit from
/// Range-based chunked transfer.
class FilePreviewScreen extends StatefulWidget {
  final String base;
  final String sessionToken;
  final String alias;
  final String remotePath;
  final String fileName;
  final int fileSize;

  const FilePreviewScreen({
    super.key,
    required this.base,
    required this.sessionToken,
    required this.alias,
    required this.remotePath,
    required this.fileName,
    required this.fileSize,
  });

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  Uint8List? _data;
  bool _loading = true;
  String? _error;
  double _progress = 0;

  late final ResumableDownloadManager _downloader;

  @override
  void initState() {
    super.initState();
    _downloader = ResumableDownloadManager(
      base: widget.base,
      sessionToken: widget.sessionToken,
    );
    _load();
  }

  @override
  void dispose() {
    _downloader.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _progress = 0;
    });
    try {
      final bytes = await _downloader.download(
        alias: widget.alias,
        remotePath: widget.remotePath,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p.fraction);
        },
      );
      if (mounted) {
        setState(() {
          _data = bytes;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = _previewKind(widget.fileName);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        actions: [
          if (!_loading && _error == null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reload',
              onPressed: _load,
            ),
        ],
      ),
      body: _buildBody(kind),
    );
  }

  Widget _buildBody(_PreviewKind kind) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(value: _progress > 0 ? _progress : null),
            const SizedBox(height: 16),
            Text(
              _progress > 0
                  ? '${(_progress * 100).toStringAsFixed(0)}%'
                  : 'Loading…',
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final data = _data!;

    switch (kind) {
      case _PreviewKind.image:
        return InteractiveViewer(
          child: Center(child: Image.memory(data, fit: BoxFit.contain)),
        );

      case _PreviewKind.text:
        final text = _tryDecodeUtf8(data);
        if (text == null) return _binaryFallback(data);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            text,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        );

      case _PreviewKind.binary:
        return _binaryFallback(data);
    }
  }

  Widget _binaryFallback(Uint8List data) {
    final kb = (data.length / 1024).toStringAsFixed(1);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.insert_drive_file, size: 72, color: Colors.grey),
          const SizedBox(height: 16),
          Text(widget.fileName,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('$kb KB — no preview available',
              style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          Text(
            _hexDump(data, maxBytes: 256),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: Colors.grey,
            ),
          ),
        ],
      ),
    );
  }

  String? _tryDecodeUtf8(Uint8List data) {
    try {
      return utf8.decode(data);
    } catch (_) {
      return null;
    }
  }

  String _hexDump(Uint8List data, {int maxBytes = 256}) {
    final buf = StringBuffer();
    final limit = data.length < maxBytes ? data.length : maxBytes;
    for (var i = 0; i < limit; i += 16) {
      final end = (i + 16) < limit ? i + 16 : limit;
      final hex = data
          .sublist(i, end)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join(' ');
      buf.writeln(hex);
    }
    if (data.length > maxBytes) buf.write('… (${data.length} bytes total)');
    return buf.toString();
  }
}
