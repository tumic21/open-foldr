import 'package:flutter/material.dart';

/// Returns the chosen new name, or null if cancelled.
Future<String?> showRenameDialog(
  BuildContext context, {
  required String currentName,
}) {
  final controller = TextEditingController(text: currentName);
  // Select the name without the extension so the user can type immediately.
  final dotIndex = currentName.lastIndexOf('.');
  final selectEnd =
      dotIndex > 0 ? dotIndex : currentName.length;
  controller.selection =
      TextSelection(baseOffset: 0, extentOffset: selectEnd);

  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'New name',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) {
          final name = v.trim();
          if (name.isNotEmpty &&
              !name.contains('/') &&
              name != '..') {
            Navigator.pop(ctx, name);
          }
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final name = controller.text.trim();
            if (name.isNotEmpty &&
                !name.contains('/') &&
                name != '..') {
              Navigator.pop(ctx, name);
            }
          },
          child: const Text('Rename'),
        ),
      ],
    ),
  );
}
