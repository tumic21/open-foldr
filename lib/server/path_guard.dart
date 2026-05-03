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
      final real = File(path).absolute.path;
      // Normalize separators and remove trailing slash.
      return p.normalize(real).replaceAll(RegExp(r'[/\\]+$'), '');
    } catch (_) {
      return p.normalize(path).replaceAll(RegExp(r'[/\\]+$'), '');
    }
  }
}
