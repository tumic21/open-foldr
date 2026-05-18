part of 'file_manager_screen.dart';

extension _FileManagerScreenOpening on _FileManagerScreenState {
  void _handleTap(FileEntry entry) {
    if (_state.multiSelectMode) {
      _state.toggleSelect(entry.path);
      return;
    }
    _openEntry(entry);
  }

  /// Navigates into a directory or opens a file. Used as the double-click
  /// action on desktop and the single-tap action on mobile.
  void _openEntry(FileEntry entry) {
    if (entry.isDirectory) {
      _state.pushPath(entry.path);
      _state.clearSelection();
      _lastSelectedPath = null;
      if (_searchActive) _closeSearch();
      _load();
    } else {
      _openFile(entry);
    }
  }

  /// Desktop single-click: select with optional Ctrl / Shift modifiers.
  void _handleDesktopClick(FileEntry entry) {
    final ctrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final shift = HardwareKeyboard.instance.isShiftPressed;

    if (shift && _lastSelectedPath != null) {
      // Range-select between anchor and clicked item.
      final visible = _state.filteredEntries;
      final anchorIdx = visible.indexWhere((e) => e.path == _lastSelectedPath);
      final clickIdx = visible.indexWhere((e) => e.path == entry.path);
      if (anchorIdx >= 0 && clickIdx >= 0) {
        final lo = min(anchorIdx, clickIdx);
        final hi = max(anchorIdx, clickIdx);
        if (!ctrl) _state.clearSelection();
        for (var i = lo; i <= hi; i++) {
          if (!_state.selectedPaths.contains(visible[i].path)) {
            _state.toggleSelect(visible[i].path);
          }
        }
      }
    } else if (ctrl) {
      // Toggle this item without disturbing others.
      _state.toggleSelect(entry.path);
      _lastSelectedPath = entry.path;
    } else {
      // Plain click: select only this item.
      _state.clearSelection();
      _state.toggleSelect(entry.path);
      _lastSelectedPath = entry.path;
    }
  }

  bool _isTextFile(String name) {
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
        : '';
    const textExts = {
      'txt',
      'md',
      'markdown',
      'json',
      'yaml',
      'yml',
      'toml',
      'csv',
      'html',
      'htm',
      'xml',
      'svg',
      'css',
      'js',
      'mjs',
      'ts',
      'dart',
      'py',
      'sh',
      'bash',
      'bat',
      'log',
      'ini',
      'cfg',
      'conf',
      'c',
      'h',
      'cpp',
      'cc',
      'cxx',
      'hpp',
      'java',
      'go',
      'rs',
    };
    return textExts.contains(ext);
  }

  bool _isImageFile(String name) {
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
        : '';
    const imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'ico'};
    return imageExts.contains(ext);
  }

  bool _isPdfFile(String name) {
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
        : '';
    return ext == 'pdf';
  }

  void _openFile(FileEntry entry) {
    if (_isTextFile(entry.name)) {
      widget.onOpenFile?.call('text', entry);
      if (widget.onOpenFile != null) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TextEditorScreen(
            client: widget.client,
            alias: widget.alias,
            remotePath: entry.path,
            fileName: entry.name,
            fileSize: entry.size,
            canWrite: _canWrite,
          ),
        ),
      );
      return;
    }

    if (_isImageFile(entry.name)) {
      widget.onOpenFile?.call('image', entry);
      if (widget.onOpenFile != null) return;
      final imageEntries = _state.entries
          .where((e) => e.isFile && _isImageFile(e.name))
          .toList();
      final initialIndex = imageEntries.indexWhere((e) => e.path == entry.path);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImagePreviewScreen(
            client: widget.client,
            alias: widget.alias,
            remotePath: entry.path,
            fileName: entry.name,
            imageEntries: imageEntries,
            initialIndex: initialIndex < 0 ? 0 : initialIndex,
          ),
        ),
      );
      return;
    }

    if (_isPdfFile(entry.name)) {
      widget.onOpenFile?.call('pdf', entry);
      if (widget.onOpenFile != null) return;
      if (_isDesktop) {
        unawaited(_openDesktopPdf(entry));
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PdfPreviewScreen(
            client: widget.client,
            alias: widget.alias,
            remotePath: entry.path,
            fileName: entry.name,
          ),
        ),
      );
      return;
    }

    // Unsupported previews fall back to direct download.
    widget.onOpenFile?.call('download', entry);
    if (widget.onOpenFile != null) return;
    _confirmBinaryDownload(entry).then((confirmed) {
      if (!confirmed || !mounted) return;
      _downloadFile(entry.path, entry.name);
    });
  }
}
