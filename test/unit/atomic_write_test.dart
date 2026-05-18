import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_foldr/core/atomic_write.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('atomic_write_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  test('creates a new file with correct content', () async {
    final target = '${tempDir.path}/output.txt';
    final content = 'hello world';

    await atomicWrite(
      target,
      Stream.value(content.codeUnits.map((c) => c).toList()),
    );

    expect(File(target).existsSync(), isTrue);
    expect(File(target).readAsStringSync(), content);
  });

  test('overwrites an existing file atomically', () async {
    final target = '${tempDir.path}/output.txt';
    File(target).writeAsStringSync('old content');

    await atomicWrite(
      target,
      Stream.value('new content'.codeUnits.toList()),
    );

    expect(File(target).readAsStringSync(), 'new content');
  });

  test('leaves no temp file on success', () async {
    final target = '${tempDir.path}/clean.txt';

    await atomicWrite(target, Stream.value([65, 66, 67]));

    final leftover = tempDir
        .listSync()
        .where((e) => e.path.contains('.~'))
        .toList();
    expect(leftover, isEmpty);
  });

  test('cleans up temp file on failure', () async {
    final target = '${tempDir.path}/nonexistent_dir/file.txt';

    await expectLater(
      () => atomicWrite(target, Stream.value([1, 2, 3])),
      throwsA(isA<FileSystemException>()),
    );

    // No leftover temp files in the base directory.
    final leftover = tempDir
        .listSync()
        .where((e) => e.path.contains('.~'))
        .toList();
    expect(leftover, isEmpty);
  });

  test('handles empty data stream', () async {
    final target = '${tempDir.path}/empty.bin';

    await atomicWrite(target, const Stream.empty());

    expect(File(target).existsSync(), isTrue);
    expect(File(target).lengthSync(), 0);
  });
}
