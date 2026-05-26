import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

const String androidDownloadsFolderPath = '/storage/emulated/0/Download';
const String androidDocumentsFolderPath = '/storage/emulated/0/Documents';
const String androidPicturesFolderPath = '/storage/emulated/0/Pictures';
const String androidDcimFolderPath = '/storage/emulated/0/DCIM';
const String androidMoviesFolderPath = '/storage/emulated/0/Movies';
const String androidMusicFolderPath = '/storage/emulated/0/Music';

const String _pickerSentinel = '__picker__';

class _AndroidShortcut {
  final String label;
  final String path;

  const _AndroidShortcut({required this.label, required this.path});
}

class _AndroidShortcutOption {
  final _AndroidShortcut shortcut;
  final bool isAvailable;

  const _AndroidShortcutOption({
    required this.shortcut,
    required this.isAvailable,
  });
}

const List<_AndroidShortcut> _defaultAndroidShortcuts = [
  _AndroidShortcut(label: 'Downloads', path: androidDownloadsFolderPath),
  _AndroidShortcut(label: 'Documents', path: androidDocumentsFolderPath),
  _AndroidShortcut(label: 'Pictures', path: androidPicturesFolderPath),
  _AndroidShortcut(label: 'DCIM', path: androidDcimFolderPath),
  _AndroidShortcut(label: 'Movies', path: androidMoviesFolderPath),
  _AndroidShortcut(label: 'Music', path: androidMusicFolderPath),
];

/// Selects a folder path to share.
///
/// On Android, this offers direct shortcuts for common protected folders
/// because the system picker may refuse them on some devices.
Future<String?> selectSharedFolderPath(
  BuildContext context, {
  bool? isAndroidOverride,
  Future<String?> Function()? pickDirectory,
  bool Function(String path)? folderExistsOverride,
}) async {
  final isAndroid = isAndroidOverride ?? Platform.isAndroid;
  final directoryPicker = pickDirectory ?? FilePicker.getDirectoryPath;
  final folderExists = folderExistsOverride ?? _folderExists;

  if (!isAndroid) {
    return directoryPicker();
  }

  final shortcuts = _defaultAndroidShortcuts
      .map(
        (shortcut) => _AndroidShortcutOption(
          shortcut: shortcut,
          isAvailable: folderExists(shortcut.path),
        ),
      )
      .toList(growable: false);

  final choice = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Add folder'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Select a protected folder below, or use the picker for any '
                'other location.',
              ),
              const SizedBox(height: 12),
              for (final option in shortcuts) ...[
                _buildShortcutTile(dialogContext, option),
                const SizedBox(height: 6),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(dialogContext, _pickerSentinel),
          icon: const Icon(Icons.folder_open),
          label: const Text('Choose another folder'),
        ),
      ],
    ),
  );

  if (choice == null) return null;
  if (choice == _pickerSentinel) return directoryPicker();
  return choice;
}

bool _folderExists(String path) => Directory(path).existsSync();

Widget _buildShortcutTile(BuildContext context, _AndroidShortcutOption option) {
  final shortcut = option.shortcut;
  final available = option.isAvailable;
  final theme = Theme.of(context);
  return ListTile(
    dense: true,
    visualDensity: VisualDensity.compact,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    tileColor: available
        ? theme.colorScheme.surfaceContainerLow
        : theme.colorScheme.surfaceContainerHighest,
    enabled: available,
    leading: Icon(
      Icons.folder,
      color: available ? theme.colorScheme.primary : theme.colorScheme.outline,
    ),
    title: Text(shortcut.label),
    subtitle: Text(shortcut.path),
    trailing: Icon(
      available ? Icons.arrow_forward : Icons.lock_outline,
      size: 18,
    ),
    onTap: available ? () => Navigator.pop(context, shortcut.path) : null,
  );
}
