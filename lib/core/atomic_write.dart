import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

final _uuid = const Uuid();

/// Writes [data] to [targetPath] atomically:
/// 1. Write to a sibling temp file in the same directory.
/// 2. Flush and close the temp file (fsync where available).
/// 3. Rename the temp file to [targetPath] (atomic on POSIX, best-effort on Windows).
///
/// On failure the temp file is deleted. Throws on I/O errors.
Future<void> atomicWrite(String targetPath, Stream<List<int>> data) async {
  final dir = p.dirname(targetPath);
  final tmpPath = p.join(dir, '.~${p.basename(targetPath)}.${_uuid.v4()}');
  final tmp = File(tmpPath);
  IOSink? sink;
  try {
    sink = tmp.openWrite();
    await sink.addStream(data);
    await sink.flush();
    await sink.close();
    sink = null;
    await tmp.rename(targetPath);
  } catch (e) {
    sink?.close().catchError((_) => ());
    if (await tmp.exists()) {
      await tmp.delete().catchError((_) => File(tmpPath));
    }
    rethrow;
  }
}
