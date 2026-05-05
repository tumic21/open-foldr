import 'package:flutter/material.dart';

enum ConflictResolution { skip, replace, keepBoth }

/// Shown when a paste/copy detects a 409 conflict on a specific item.
///
/// Returns the chosen [ConflictResolution], or null if the dialog is dismissed.
Future<ConflictResolution?> showConflictDialog(
  BuildContext context, {
  required String itemName,
}) {
  return showDialog<ConflictResolution>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('File Already Exists'),
      content: Text(
        '"$itemName" already exists at the destination.\n'
        'How would you like to proceed?',
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, ConflictResolution.skip),
          child: const Text('Skip'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, ConflictResolution.keepBoth),
          child: const Text('Keep Both'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.orange),
          onPressed: () =>
              Navigator.pop(ctx, ConflictResolution.replace),
          child: const Text('Replace'),
        ),
      ],
    ),
  );
}
