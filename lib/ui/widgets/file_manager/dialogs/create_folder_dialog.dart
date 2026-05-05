import 'package:flutter/material.dart';

/// Returns the new folder name, or null if cancelled.
Future<String?> showCreateFolderDialog(BuildContext context) {
  final controller = TextEditingController();

  bool isValid(String v) =>
      v.isNotEmpty && !v.contains('/') && v != '..';

  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('New Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Folder name',
            border: const OutlineInputBorder(),
            errorText: controller.text.isNotEmpty && !isValid(controller.text)
                ? 'Name cannot contain / or be ..'
                : null,
          ),
          onChanged: (_) => setState(() {}),
          onSubmitted: (v) {
            if (isValid(v.trim())) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: isValid(controller.text.trim())
                ? () => Navigator.pop(ctx, controller.text.trim())
                : null,
            child: const Text('Create'),
          ),
        ],
      ),
    ),
  );
}
