part of 'file_manager_screen.dart';

extension _FileManagerScreenDragDrop on _FileManagerScreenState {
  List<String> _dragPayloadForEntry(FileEntry entry) {
    if (_state.multiSelectMode &&
        _state.selectedPaths.isNotEmpty &&
        _state.selectedPaths.contains(entry.path)) {
      return _state.selectedPaths.toList(growable: false);
    }
    return [entry.path];
  }

  void _handleDragStarted(FileEntry entry) {
    final payload = _dragPayloadForEntry(entry);

    // Single-item drag on desktop enters multi-select and auto-selects item.
    if (!_state.multiSelectMode && payload.length == 1) {
      _state.clearSelection();
      _state.toggleSelect(entry.path);
    }
  }

  void _handleDragCompleted() {}

  bool _isInvalidMove(String source, String destination) {
    if (source == destination) return true;
    return destination.startsWith('$source/');
  }

  Future<void> _moveDraggedPaths(List<String> paths, String destination) async {
    if (!_canWrite) return;
    if (paths.isEmpty) return;

    final unique = paths.toSet().toList(growable: false);
    if (unique.any((src) => _isInvalidMove(src, destination))) {
      _showError('Cannot move an item into itself or its subfolder.');
      return;
    }

    final result = await widget.client.batchMove(
      widget.alias,
      unique,
      destination,
    );
    if (!mounted) return;
    if (result.isErr) {
      _showError(result.errorMessage);
      return;
    }
    _state.clearSelection();
    await _load();
  }

  Future<void> _uploadDroppedFiles(List<String> filePaths) async {
    if (!_canWrite || filePaths.isEmpty) return;

    final uploadManager = ResumableUploadManager(
      base: widget.client.baseUrl,
      sessionToken: widget.client.sessionToken,
    );

    try {
      for (final path in filePaths) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final fileName = p.basename(path);
        final remotePath =
            '${_state.currentPath == '/' ? '' : _state.currentPath}/$fileName';

        setState(() {
          _uploadProgress[path] = UploadProgressItem(
            name: fileName,
            progress: 0,
          );
        });

        final bytes = await file.readAsBytes();
        try {
          await uploadManager.upload(
            alias: widget.alias,
            remotePath: remotePath,
            bytes: bytes,
            onProgress: (progress) {
              if (!mounted) return;
              setState(() {
                _uploadProgress[path] = UploadProgressItem(
                  name: fileName,
                  progress: progress.fraction,
                  complete: progress.complete,
                );
              });
            },
          );
          if (!mounted) return;
          setState(() {
            _uploadProgress[path] = UploadProgressItem(
              name: fileName,
              progress: 1,
              complete: true,
            );
          });
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _uploadProgress[path] = UploadProgressItem(
              name: fileName,
              progress: 0,
              error: e.toString(),
            );
          });
        }
      }

      await _load();
    } finally {
      uploadManager.dispose();
      if (mounted) {
        Future<void>.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          setState(() => _uploadProgress.clear());
        });
      }
    }
  }
}
