import 'package:flutter/material.dart';

/// A scrollable horizontal breadcrumb navigation bar.
///
/// Shows the root [alias] followed by path segments derived from [currentPath].
/// Tapping an ancestor segment calls [onNavigateTo] with that segment's path.
class BreadcrumbBar extends StatelessWidget {
  final String alias;
  final String currentPath;
  final void Function(String path)? onNavigateTo;

  const BreadcrumbBar({
    super.key,
    required this.alias,
    required this.currentPath,
    this.onNavigateTo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Build list of (label, path) pairs for each breadcrumb segment.
    final segments = <(String, String)>[(alias, '/')];
    if (currentPath != '/') {
      final parts =
          currentPath.split('/').where((s) => s.isNotEmpty).toList();
      var accumulated = '';
      for (final part in parts) {
        accumulated = '$accumulated/$part';
        segments.add((part, accumulated));
      }
    }

    return Container(
      height: 40,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (int i = 0; i < segments.length; i++) ...[
              if (i > 0)
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              InkWell(
                onTap: i < segments.length - 1 && onNavigateTo != null
                    ? () => onNavigateTo!(segments[i].$2)
                    : null,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  child: Text(
                    segments[i].$1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: i == segments.length - 1
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: i == segments.length - 1
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
