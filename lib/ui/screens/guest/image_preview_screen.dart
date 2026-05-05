import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../client/file_client.dart';

class ImagePreviewScreen extends StatefulWidget {
  final FileClient client;
  final String alias;
  final String remotePath;
  final String fileName;

  const ImagePreviewScreen({
    super.key,
    required this.client,
    required this.alias,
    required this.remotePath,
    required this.fileName,
  });

  @override
  State<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends State<ImagePreviewScreen> {
  bool _loading = true;
  String? _error;
  ImageProvider? _provider;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _provider = null;
    });

    final result =
        await widget.client.downloadFile(widget.alias, widget.remotePath);
    if (!mounted) return;

    if (result.isErr) {
      setState(() {
        _loading = false;
        _error = result.errorMessage;
      });
      return;
    }

    final bytes = result.unwrap;
    final memory = MemoryImage(bytes);
    final stream = memory.resolve(const ImageConfiguration());

    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (imageInfo, _) {
        stream.removeListener(listener);
        if (!mounted) return;

        // Avoid huge decodes for very large images by downscaling to <= 8 MP.
        final w = imageInfo.image.width;
        final h = imageInfo.image.height;
        final pixels = w * h;
        if (pixels > 8 * 1000 * 1000) {
          final ratio = math.sqrt(pixels / (8 * 1000 * 1000));
          final targetW = (w / ratio).round();
          final targetH = (h / ratio).round();
          _provider = ResizeImage(memory, width: targetW, height: targetH);
        } else {
          _provider = memory;
        }

        setState(() => _loading = false);
      },
      onError: (_, stackTrace) {
        stream.removeListener(listener);
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Could not decode image file.';
        });
      },
    );

    stream.addListener(listener);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.fileName),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload',
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.broken_image_outlined, size: 48),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return InteractiveViewer(
      minScale: 0.5,
      maxScale: 6,
      child: Center(
        child: Image(image: _provider!, fit: BoxFit.contain),
      ),
    );
  }
}
