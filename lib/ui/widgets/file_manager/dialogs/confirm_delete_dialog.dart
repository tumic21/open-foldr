import 'package:flutter/material.dart';

/// Returns true if the user confirmed deletion.
Future<bool> showConfirmDeleteDialog(
  BuildContext context, {
  required int itemCount,
  String? itemName,
}) {
  final isSingle = itemCount == 1;
  final label = isSingle && itemName != null
      ? '"$itemName"'
      : '$itemCount item${itemCount == 1 ? '' : 's'}';

  return showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Confirm Delete'),
      content: Text('Delete $label? This cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  ).then((v) => v ?? false);
}
