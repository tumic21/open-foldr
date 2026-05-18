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
      _showResultError(result, operation: 'move these items');
      return;
    }

    _showBatchFailures(result.unwrap, operation: 'move these items');
    _state.clearSelection();
    await _load();
  }

  Future<void> _uploadDroppedFiles(List<String> filePaths) async {
    if (!_canWrite || filePaths.isEmpty) return;

    // Get current directory entries to check for conflicts
    final listResult = await widget.client.listEntries(
      widget.alias,
      _state.currentPath,
    );
    if (!mounted) return;
    if (listResult.isErr) {
      _showError('Could not check for existing files');
      return;
    }
    final existingEntries = listResult.unwrap;
    final existingNames = {for (final e in existingEntries) e.name: e};

    final uploadManager = ResumableUploadManager(
      base: widget.client.baseUrl,
      sessionToken: widget.client.sessionToken,
    );

    // Check which files have conflicts
    final filesToUpload = <String, String>{}; // local path -> remote path
    UploadConflictResolution? applyToAllResolution;

    try {
      for (final path in filePaths) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final fileName = p.basename(path);
        
        String remotePath =
            '${_state.currentPath == '/' ? '' : _state.currentPath}/$fileName';

        // Check for conflict
        if (existingNames.containsKey(fileName)) {
          // Show dialog if we haven't already applied a global resolution
          if (applyToAllResolution == null) {
            if (!mounted) return;
            final conflictResult = await showUploadConflictDialog(
              context,
              fileName: fileName,
              allowApplyToAll: filePaths.length > 1,
            );

            if (!mounted) return;
            if (conflictResult == null ||
                conflictResult.resolution == UploadConflictResolution.cancel) {
              return; // Cancel entire upload
            }

            if (conflictResult.applyToAll) {
              applyToAllResolution = conflictResult.resolution;
            } else {
              // Handle this single file
              if (conflictResult.resolution == UploadConflictResolution.rename) {
                final ext = fileName.contains('.')
                    ? fileName.substring(fileName.lastIndexOf('.'))
                    : '';
                final base = ext.isNotEmpty
                    ? fileName.substring(0, fileName.lastIndexOf('.'))
                    : fileName;
                final newFileName =
                    '${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
                remotePath = '${_state.currentPath == '/' ? '' : _state.currentPath}/$newFileName';
              }
              // For overwrite, use the same remotePath
            }
          } else {
            // Apply the global resolution
            if (applyToAllResolution == UploadConflictResolution.rename) {
              final ext = fileName.contains('.')
                  ? fileName.substring(fileName.lastIndexOf('.'))
                  : '';
              final base = ext.isNotEmpty
                  ? fileName.substring(0, fileName.lastIndexOf('.'))
                  : fileName;
              final newFileName =
                  '${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
              remotePath =
                  '${_state.currentPath == '/' ? '' : _state.currentPath}/$newFileName';
            }
            // For overwrite, use the same remotePath
          }
        }

        filesToUpload[path] = remotePath;
      }

      // Upload all files
      for (final entry in filesToUpload.entries) {
        final path = entry.key;
        final remotePath = entry.value;
        final file = File(path);
        final fileName = p.basename(path);

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
