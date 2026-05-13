import 'dart:io';
import 'package:path/path.dart' as p;
import '../core/result.dart';
export '../core/result.dart';

/// Validates and resolves file system paths to prevent sandbox escape.
///
/// All path operations MUST pass through [resolve] before any I/O.
class PathGuard {
  final String rootPath;
  final String _canonicalRoot;

  PathGuard(this.rootPath)
      : _canonicalRoot = _canonicalize(rootPath);

  /// Resolves [relativePath] against the shared root.
  ///
  /// Returns [Ok] with the safe absolute path, or [Err] with code
  /// INVALID_ARGUMENT if the path escapes the sandbox.
  Result<String> resolve(String relativePath) {
    // Reject absolute paths up front.
    if (p.isAbsolute(relativePath)) {
      return const Err('INVALID_ARGUMENT', 'Absolute paths are not allowed');
    }

    // Reject obvious traversal attempts before canonicalization.
    final normalized = p.normalize(relativePath);
    if (normalized.startsWith('..')) {
      return const Err('INVALID_ARGUMENT', 'Path traversal is not allowed');
    }

    final joined = p.join(_canonicalRoot, normalized);
    final canonical = _canonicalize(joined);

    if (!canonical.startsWith(_canonicalRoot + Platform.pathSeparator) &&
        canonical != _canonicalRoot) {
      return const Err('INVALID_ARGUMENT', 'Path escapes shared root');
    }

    return Ok(canonical);
  }

  /// Checks that [absolutePath] is still within the root after open.
  /// Helps reduce TOCTOU risk.
  bool isWithinRoot(String absolutePath) {
    final canonical = _canonicalize(absolutePath);
    return canonical.startsWith(_canonicalRoot + Platform.pathSeparator) ||
        canonical == _canonicalRoot;
  }

  static String _canonicalize(String path) {
    try {
      final absolute = p.normalize(File(path).absolute.path);
      final type = FileSystemEntity.typeSync(absolute, followLinks: false);
      final real = switch (type) {
        FileSystemEntityType.directory => Directory(
          absolute,
        ).resolveSymbolicLinksSync(),
        FileSystemEntityType.file => File(absolute).resolveSymbolicLinksSync(),
        FileSystemEntityType.link => Link(absolute).resolveSymbolicLinksSync(),
        _ => _resolveExistingAncestor(absolute),
      };
      // Normalize separators and remove trailing slash.
      return p.normalize(real).replaceAll(RegExp(r'[/\\]+$'), '');
    } catch (_) {
      return p.normalize(path).replaceAll(RegExp(r'[/\\]+$'), '');
    }
  }

  static String _resolveExistingAncestor(String absolutePath) {
    var cursor = absolutePath;
    final suffix = <String>[];

    while (FileSystemEntity.typeSync(cursor, followLinks: false) ==
      FileSystemEntityType.notFound) {
      final parent = p.dirname(cursor);
      if (parent == cursor) {
        return absolutePath;
      }
      suffix.insert(0, p.basename(cursor));
      cursor = parent;
    }

    final type = FileSystemEntity.typeSync(cursor, followLinks: false);
    final resolvedBase = switch (type) {
      FileSystemEntityType.directory => Directory(
        cursor,
      ).resolveSymbolicLinksSync(),
      FileSystemEntityType.file => File(cursor).resolveSymbolicLinksSync(),
      FileSystemEntityType.link => Link(cursor).resolveSymbolicLinksSync(),
      _ => cursor,
    };

    return suffix.isEmpty ? resolvedBase : p.joinAll([resolvedBase, ...suffix]);
  }
}
