import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../client/file_client.dart';
import 'file_type_icon.dart';

class FileGridTile extends StatelessWidget {
  final FileEntry entry;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const FileGridTile({
    super.key,
    required this.entry,
    this.selected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Card(
        color: selected ? theme.colorScheme.primaryContainer : null,
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Align(
                alignment: Alignment.topRight,
                child: SizedBox(
                  height: 24,
                  child: selected
                      ? Icon(
                          Icons.check_circle,
                          color: theme.colorScheme.primary,
                          size: 20,
                        )
                      : null,
                ),
              ),
              Icon(
                entry.isDirectory ? Icons.folder : fileTypeIcon(entry.name),
                size: 48,
                color: entry.isDirectory
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 6),
              Text(
                entry.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
              if (!entry.isDirectory)
                Text(
                  DateFormat.yMMMd().format(entry.modifiedAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
