import 'package:flutter/material.dart';

import '../../../client/file_client.dart';
import '../../services/thumbnail_service.dart';
import 'file_type_icon.dart';

class FileThumbnail extends StatefulWidget {
  final FileClient client;
  final String alias;
  final FileEntry entry;
  final double size;
  final int? requestSize;
  final BoxFit fit;
  final ThumbnailService service;

  const FileThumbnail({
    super.key,
    required this.client,
    required this.alias,
    required this.entry,
    required this.size,
    this.requestSize,
    this.fit = BoxFit.cover,
    this.service = ThumbnailService.instance,
  });

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  late Future<Result<ThumbnailResponse>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant FileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.alias != widget.alias ||
        oldWidget.entry.path != widget.entry.path ||
        oldWidget.requestSize != widget.requestSize ||
        oldWidget.fit != widget.fit ||
        oldWidget.service != widget.service) {
      _future = _load();
    }
  }

  Future<Result<ThumbnailResponse>> _load() {
    final target = _targetSize();
    return widget.service.getThumbnail(
      client: widget.client,
      alias: widget.alias,
      path: widget.entry.path,
      width: target,
      height: target,
      fit: widget.fit == BoxFit.contain ? 'contain' : 'cover',
    );
  }

  int _targetSize() {
    final explicit = widget.requestSize;
    if (explicit != null) {
      return explicit.clamp(24, 512);
    }
    return widget.size.round().clamp(24, 512);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entry.isDirectory || !isImageFileName(widget.entry.name)) {
      final fd = widget.entry.isDirectory
          ? folderIconData(context)
          : fileTypeIcon(widget.entry.name, context);
      return Icon(fd.icon, color: fd.color, size: widget.size);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: FutureBuilder<Result<ThumbnailResponse>>(
        future: _future,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return _buildPlaceholder(context);
          }

          final result = snapshot.data!;
          if (result.isErr || result.unwrap.bytes == null) {
            return _buildFallback(context);
          }

          return Image.memory(
            result.unwrap.bytes!,
            width: widget.size,
            height: widget.size,
            fit: widget.fit,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
          );
        },
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.image_outlined,
            size: widget.size * 0.55,
            color: scheme.outline,
          ),
        ),
      ),
    );
  }

  Widget _buildFallback(BuildContext context) {
    final fd = fileTypeIcon(widget.entry.name, context);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(fd.icon, color: fd.color, size: widget.size * 0.65),
        ),
      ),
    );
  }
}
