import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../client/file_client.dart';
import 'file_thumbnail.dart';

class FileGridTile extends StatelessWidget {
  final FileClient client;
  final String alias;
  final FileEntry entry;
  final bool selected;
  final bool multiSelectMode;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final List<String>? draggablePaths;
  final VoidCallback? onDragStarted;
  final VoidCallback? onDragCompleted;
  final void Function(List<String> paths)? onDropPaths;

  const FileGridTile({
    super.key,
    required this.client,
    required this.alias,
    required this.entry,
    this.selected = false,
    this.multiSelectMode = false,
    this.onTap,
    this.onDoubleTap,
    this.onLongPress,
    this.draggablePaths,
    this.onDragStarted,
    this.onDragCompleted,
    this.onDropPaths,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);
    // On desktop (onDoubleTap != null) hide the checkbox indicator and use a
    // stronger card colour for selection contrast instead.
    final bool useGesture = onDoubleTap != null;
    final bool showCheckbox = multiSelectMode && !useGesture;
    final Color? cardColor = selected
        ? (useGesture
            ? theme.colorScheme.primaryContainer.withAlpha(230)
            : theme.colorScheme.primaryContainer)
        : null;
    Widget tile = GestureDetector(
      onTap: onTap,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      child: Card(
        color: cardColor,
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final shortestSide = MediaQuery.sizeOf(context).shortestSide;
            final compactPhone = shortestSide < 420;
            final thumbSize = constraints.maxHeight < 168 ? 42.0 : 48.0;
            final showDate = !entry.isDirectory &&
                !compactPhone &&
                constraints.maxHeight >= 172 &&
                textScale <= 1.15;
            final nameMaxLines = showDate ? 2 : 3;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Column(
                children: [
                  SizedBox(
                    height: 20,
                    child: showCheckbox
                        ? Align(
                            alignment: Alignment.topRight,
                            child: Icon(
                              selected
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              color: selected
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.outline,
                              size: 20,
                            ),
                          )
                        : null,
                  ),
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          FileThumbnail(
                            client: client,
                            alias: alias,
                            entry: entry,
                            size: thumbSize,
                            requestSize: 128,
                            fit: BoxFit.cover,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            entry.name,
                            textAlign: TextAlign.center,
                            maxLines: nameMaxLines,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          if (showDate)
                            Text(
                              DateFormat.yMMMd().format(entry.modifiedAt),
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );

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
              borderRadius: BorderRadius.circular(10),
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
              style: theme.textTheme.bodySmall,
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.45, child: tile),
        child: tile,
      );
    }

    return tile;
  }
}
