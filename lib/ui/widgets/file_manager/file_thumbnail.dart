import 'package:flutter/material.dart';
import 'package:visibility_detector/visibility_detector.dart';

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
  final ThumbnailService? service;

  const FileThumbnail({
    super.key,
    required this.client,
    required this.alias,
    required this.entry,
    required this.size,
    this.requestSize,
    this.fit = BoxFit.cover,
    this.service,
  });

  @override
  State<FileThumbnail> createState() => _FileThumbnailState();
}

class _FileThumbnailState extends State<FileThumbnail> {
  Future<Result<ThumbnailResponse>>? _future;
  bool _hasStartedLoading = false;

  ThumbnailService get _service => widget.service ?? ThumbnailService.instance;

  @override
  void didUpdateWidget(covariant FileThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.alias != widget.alias ||
        oldWidget.entry.path != widget.entry.path ||
        oldWidget.requestSize != widget.requestSize ||
        oldWidget.fit != widget.fit ||
        oldWidget.service != widget.service) {
      _future = null;
      _hasStartedLoading = false;
    }
  }

  Future<Result<ThumbnailResponse>> _load() {
    final target = _targetSize();
    return _service.getThumbnail(
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

  void _handleVisibilityChanged(VisibilityInfo info) {
    if (_hasStartedLoading || info.visibleFraction <= 0) return;
    _hasStartedLoading = true;
    setState(() {
      _future = _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entry.isDirectory || !isImageFileName(widget.entry.name)) {
      final fd = widget.entry.isDirectory
          ? folderIconData(context)
          : fileTypeIcon(widget.entry.name, context);
      return Icon(fd.icon, color: fd.color, size: widget.size);
    }

    return VisibilityDetector(
      key: ValueKey(
        'thumb:${widget.alias}:${widget.entry.path}:${widget.requestSize ?? widget.size}:${widget.fit.name}',
      ),
      onVisibilityChanged: _handleVisibilityChanged,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: FutureBuilder<Result<ThumbnailResponse>>(
          future: _future,
          builder: (context, snapshot) {
            if (_future == null || !snapshot.hasData) {
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
              errorBuilder: (context, error, stackTrace) {
                _service.reportDecodeFailure();
                return _buildFallback(context);
              },
            );
          },
        ),
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
