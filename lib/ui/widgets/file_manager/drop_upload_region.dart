import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

class DropUploadRegion extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final Future<void> Function(List<String> filePaths) onFilesDropped;

  const DropUploadRegion({
    super.key,
    required this.child,
    required this.enabled,
    required this.onFilesDropped,
  });

  @override
  State<DropUploadRegion> createState() => _DropUploadRegionState();
}

class _DropUploadRegionState extends State<DropUploadRegion> {
  bool _dragOver = false;

  @override
  Widget build(BuildContext context) {
    return DropRegion(
      formats: const [...Formats.standardFormats],
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (event) {
        if (!widget.enabled) return DropOperation.none;
        setState(() => _dragOver = true);
        if (event.session.allowedOperations.contains(DropOperation.copy)) {
          return DropOperation.copy;
        }
        if (event.session.allowedOperations.isEmpty) {
          return DropOperation.none;
        }
        return event.session.allowedOperations.first;
      },
      onDropLeave: (event) {
        if (_dragOver) setState(() => _dragOver = false);
      },
      onDropEnded: (event) {
        if (_dragOver) setState(() => _dragOver = false);
      },
      onPerformDrop: (event) async {
        setState(() => _dragOver = false);
        if (!widget.enabled) return;
        final paths = await _extractPaths(event);
        if (paths.isNotEmpty) {
          await widget.onFilesDropped(paths);
        }
      },
      child: Stack(
        children: [
          Positioned.fill(child: widget.child),
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _dragOver ? 1 : 0,
                duration: const Duration(milliseconds: 130),
                child: Container(
                  color: Colors.black26,
                  alignment: Alignment.center,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Drop to upload',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<List<String>> _extractPaths(PerformDropEvent event) async {
    final out = <String>[];

    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null) continue;

      final fileUri = await _readFileUri(reader);
      if (fileUri != null && fileUri.scheme == 'file') {
        out.add(fileUri.toFilePath());
      }
    }

    return out.toSet().toList(growable: false);
  }

  Future<Uri?> _readFileUri(DataReader reader) async {
    final completer = Completer<Uri?>();

    final progress = reader.getValue(
      Formats.fileUri,
      (value) {
        if (!completer.isCompleted) completer.complete(value);
      },
      onError: (error) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );

    if (progress == null) return null;

    try {
      return await completer.future.timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }
}
