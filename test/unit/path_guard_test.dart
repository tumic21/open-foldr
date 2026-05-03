import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:open_foldr/server/path_guard.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late PathGuard guard;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('path_guard_test_');
    guard = PathGuard(tempDir.path);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  group('PathGuard.resolve', () {
    test('allows valid relative path', () {
      final result = guard.resolve('subdir/file.txt');
      expect(result.isOk, isTrue);
      expect(result.unwrap, startsWith(tempDir.path));
    });

    test('rejects absolute path', () {
      final result = guard.resolve('/etc/passwd');
      expect(result.isErr, isTrue);
      expect(result.errorCode, 'INVALID_ARGUMENT');
    });

    test('rejects double-dot traversal', () {
      final result = guard.resolve('../../etc/passwd');
      expect(result.isErr, isTrue);
      expect(result.errorCode, 'INVALID_ARGUMENT');
    });

    test('rejects traversal to parent after valid prefix', () {
      final result = guard.resolve('subdir/../../etc/passwd');
      expect(result.isErr, isTrue);
      expect(result.errorCode, 'INVALID_ARGUMENT');
    });

    test('allows root path', () {
      final result = guard.resolve('.');
      expect(result.isOk, isTrue);
    });

    test('allows nested path within root', () {
      Directory('${tempDir.path}/a/b').createSync(recursive: true);
      final result = guard.resolve('a/b');
      expect(result.isOk, isTrue);
      expect(result.unwrap, contains(p.join(tempDir.path, 'a', 'b')));
    });
  });

  group('PathGuard.isWithinRoot', () {
    test('returns true for path inside root', () {
      expect(guard.isWithinRoot('${tempDir.path}/foo/bar.txt'), isTrue);
    });

    test('returns false for path outside root', () {
      expect(guard.isWithinRoot('/etc/passwd'), isFalse);
    });
  });
}
