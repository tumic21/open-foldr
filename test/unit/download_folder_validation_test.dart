import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:open_foldr/ui/services/download_folder_validation.dart';

void main() {
  group('validateDownloadFolderForWrite', () {
    test('returns reason for missing folder', () async {
      final base = await Directory.systemTemp.createTemp('openfoldr-test-');
      addTearDown(() async {
        if (await base.exists()) {
          await base.delete(recursive: true);
        }
      });

      final missingPath = p.join(base.path, 'missing');
      final reason = await validateDownloadFolderForWrite(missingPath);

      expect(reason, isNotNull);
      expect(reason!.toLowerCase(), contains('does not exist'));
    });

    test('returns reason when path is not a directory', () async {
      final base = await Directory.systemTemp.createTemp('openfoldr-test-');
      addTearDown(() async {
        if (await base.exists()) {
          await base.delete(recursive: true);
        }
      });

      final filePath = p.join(base.path, 'not-a-directory.txt');
      await File(filePath).writeAsString('x');

      final reason = await validateDownloadFolderForWrite(filePath);
      expect(reason, isNotNull);
      expect(reason!.toLowerCase(), contains('not a folder'));
    });

    test('returns null for writable directory', () async {
      final base = await Directory.systemTemp.createTemp('openfoldr-test-');
      addTearDown(() async {
        if (await base.exists()) {
          await base.delete(recursive: true);
        }
      });

      final reason = await validateDownloadFolderForWrite(base.path);
      expect(reason, isNull);
    });
  });
}