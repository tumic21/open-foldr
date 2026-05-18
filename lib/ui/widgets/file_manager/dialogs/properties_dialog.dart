import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../client/file_client.dart';

/// Shows a read-only properties panel for [entry].
Future<void> showPropertiesDialog(
  BuildContext context, {
  required FileEntry entry,
}) {
  final fmt = DateFormat.yMMMMd().add_jms();
  final rows = <(String, String)>[
    ('Name', entry.name),
    ('Path', entry.path),
    ('Type', entry.isDirectory ? 'Folder' : _mimeLabel(entry.name)),
    if (entry.isFile) ('Size', _formatSize(entry.size)),
    ('Modified', fmt.format(entry.modifiedAt.toLocal())),
  ];

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Properties'),
      content: SingleChildScrollView(
        child: Table(
          columnWidths: const {
            0: IntrinsicColumnWidth(),
            1: FlexColumnWidth(),
          },
          children: rows.map((row) {
            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 12, bottom: 8),
                  child: Text(
                    row.$1,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SelectableText(row.$2),
                ),
              ],
            );
          }).toList(),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

String _mimeLabel(String name) {
  if (!name.contains('.')) return 'File';
  final ext = name.substring(name.lastIndexOf('.') + 1).toLowerCase();
  return switch (ext) {
    'jpg' || 'jpeg' => 'JPEG Image',
    'png' => 'PNG Image',
    'gif' => 'GIF Image',
    'webp' => 'WebP Image',
    'svg' => 'SVG Image',
    'pdf' => 'PDF Document',
    'mp4' || 'mkv' || 'mov' || 'avi' => 'Video',
    'mp3' || 'flac' || 'wav' || 'ogg' || 'aac' => 'Audio',
    'zip' => 'ZIP Archive',
    'tar' => 'TAR Archive',
    'gz' => 'GZip Archive',
    'json' => 'JSON File',
    'yaml' || 'yml' => 'YAML File',
    'md' => 'Markdown',
    'txt' => 'Plain Text',
    'dart' => 'Dart Source',
    _ => '${ext.toUpperCase()} File',
  };
}

String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
