import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../client/file_client.dart';
import 'file_type_icon.dart';

class FileListTile extends StatelessWidget {
  final FileEntry entry;
  final bool selected;
  final bool multiSelectMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMoreTap;

  const FileListTile({
    super.key,
    required this.entry,
    this.selected = false,
    this.multiSelectMode = false,
    this.onTap,
    this.onLongPress,
    this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      selected: selected,
      leading: multiSelectMode
          ? Checkbox(
              value: selected,
              onChanged: onTap == null ? null : (_) => onTap!(),
            )
          : Icon(
              entry.isDirectory ? Icons.folder : fileTypeIcon(entry.name),
              color: entry.isDirectory ? theme.colorScheme.primary : null,
            ),
      title: Text(entry.name, overflow: TextOverflow.ellipsis),
      subtitle: entry.isDirectory ? null : Text(_subtitle()),
      trailing: IconButton(
        icon: const Icon(Icons.more_vert, size: 18),
        onPressed: onMoreTap,
        tooltip: 'More options',
      ),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  String _subtitle() {
    final datePart = DateFormat.yMMMd().format(entry.modifiedAt);
    return '${_formatSize(entry.size)} · $datePart';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}
