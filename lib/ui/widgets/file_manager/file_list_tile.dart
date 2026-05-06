import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../client/file_client.dart';
import 'file_type_icon.dart';

class FileListTile extends StatelessWidget {
  final FileEntry entry;
  final bool selected;
  final bool multiSelectMode;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onMoreTap;
  final List<String>? draggablePaths;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragCompleted;
  final void Function(List<String> paths)? onDropPaths;

  const FileListTile({
    super.key,
    required this.entry,
    this.selected = false,
    this.multiSelectMode = false,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onMoreTap,
    this.draggablePaths,
    this.onDragStarted,
    this.onDragCompleted,
    this.onDropPaths,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // When double-tap is provided (desktop mode), remove onTap/onLongPress from
    // ListTile and wrap with a GestureDetector so all three gestures are
    // dispatched without Flutter's built-in 300 ms tap-delay.
    final bool useGesture = onDoubleTap != null;
    Widget tile = ListTile(
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
      onTap: useGesture ? null : onTap,
      onLongPress: useGesture ? null : onLongPress,
    );
    if (useGesture) {
      tile = GestureDetector(
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        onLongPress: onLongPress,
        child: tile,
      );
    }

    if (entry.isDirectory && onDropPaths != null) {
      final innerTile = tile;
      tile = DragTarget<List<String>>(
        onWillAcceptWithDetails: (details) => details.data.isNotEmpty,
        onAcceptWithDetails: (details) => onDropPaths!(details.data),
        builder: (context, candidateData, rejectedData) {
          final isTargeted = candidateData.isNotEmpty;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              border: isTargeted
                  ? Border.all(color: theme.colorScheme.primary, width: 2)
                  : null,
              borderRadius: BorderRadius.circular(8),
            ),
            child: innerTile,
          );
        },
      );
    }

    if (draggablePaths != null && draggablePaths!.isNotEmpty) {
      tile = LongPressDraggable<List<String>>(
        data: draggablePaths!,
        onDragStarted: onDragStarted,
        onDragCompleted: onDragCompleted,
        feedback: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.colorScheme.primary),
            ),
            child: Text(
              draggablePaths!.length == 1
                  ? 'Moving ${entry.name}'
                  : 'Moving ${draggablePaths!.length} items',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.45, child: tile),
        child: tile,
      );
    }

    return tile;
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
