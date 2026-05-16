import 'package:flutter/material.dart';

import '../../../client/file_client.dart';
import 'file_type_icon.dart';

class FileThumbnail extends StatelessWidget {
  final FileClient client;
  final String alias;
  final FileEntry entry;
  final double size;
  final BoxFit fit;

  const FileThumbnail({
    super.key,
    required this.client,
    required this.alias,
    required this.entry,
    required this.size,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (entry.isDirectory || !isImageFileName(entry.name)) {
      final fd = entry.isDirectory
          ? folderIconData(context)
          : fileTypeIcon(entry.name, context);
      return Icon(fd.icon, color: fd.color, size: size);
    }

    final target = size.round().clamp(24, 512);
    final uri = Uri.parse('${client.baseUrl}/roots/$alias/thumbnail').replace(
      queryParameters: {
        'path': entry.path,
        'w': '$target',
        'h': '$target',
        'fit': fit == BoxFit.contain ? 'contain' : 'cover',
      },
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        uri.toString(),
        width: size,
        height: size,
        fit: fit,
        headers: {'authorization': 'Bearer ${client.sessionToken}'},
        filterQuality: FilterQuality.low,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) return child;
          return _buildPlaceholder(context);
        },
        errorBuilder: (context, error, stackTrace) {
          final fd = fileTypeIcon(entry.name, context);
          return ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Center(
              child: Icon(fd.icon, color: fd.color, size: size * 0.65),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.image_outlined, size: size * 0.55, color: scheme.outline),
      ),
    );
  }
}
