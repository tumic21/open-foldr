import 'package:flutter/material.dart';

enum ConflictResolution { skip, replace, keepBoth }

enum UploadConflictResolution { cancel, rename, overwrite }

class UploadConflictResult {
  final UploadConflictResolution resolution;
  final bool applyToAll;

  UploadConflictResult({
    required this.resolution,
    this.applyToAll = false,
  });
}

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

/// Shown when uploading a file that already exists at the destination.
///
/// Returns [UploadConflictResult] indicating the user's choice, or null if dismissed.
Future<UploadConflictResult?> showUploadConflictDialog(
  BuildContext context, {
  required String fileName,
  bool allowApplyToAll = false,
}) {
  bool applyToAll = false;

  return showDialog<UploadConflictResult>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('File Already Exists'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"$fileName" already exists.'),
            const SizedBox(height: 16),
            const Text('What would you like to do?'),
            if (allowApplyToAll) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Apply to all'),
                value: applyToAll,
                onChanged: (value) {
                  setState(() {
                    applyToAll = value ?? false;
                  });
                },
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, UploadConflictResult(
                  resolution: UploadConflictResolution.cancel,
                  applyToAll: false,
                )),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, UploadConflictResult(
              resolution: UploadConflictResolution.rename,
              applyToAll: applyToAll,
            )),
            child: const Text('Rename'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () => Navigator.pop(ctx, UploadConflictResult(
              resolution: UploadConflictResolution.overwrite,
              applyToAll: applyToAll,
            )),
            child: const Text('Overwrite'),
          ),
        ],
      ),
    ),
  );
}
