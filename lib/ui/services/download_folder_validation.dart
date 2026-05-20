import 'dart:io';

import 'package:path/path.dart' as p;

/// Returns null when [folder] exists and is writable, otherwise a user-facing
/// reason describing why it cannot be used as a download destination.
Future<String?> validateDownloadFolderForWrite(String folder) async {
  final normalized = folder.trim();
  if (normalized.isEmpty) {
    return 'No download folder is configured.';
  }

  final type = await FileSystemEntity.type(normalized);
  if (type == FileSystemEntityType.notFound) {
    return 'The download folder does not exist.';
  }
  if (type != FileSystemEntityType.directory) {
    return 'The selected download destination is not a folder.';
  }

  final probe = File(
    p.join(
      normalized,
      '.openfoldr_write_probe_${DateTime.now().microsecondsSinceEpoch}',
    ),
  );
  try {
    await probe.writeAsBytes(const [0], flush: true);
    if (await probe.exists()) {
      await probe.delete();
    }
    return null;
  } on FileSystemException {
    return 'OpenFoldr cannot write to this folder. Choose a writable folder.';
  }
}