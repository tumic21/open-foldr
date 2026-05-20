import 'dart:async';
import 'dart:io';
import 'dart:math' show min, max;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../client/file_client.dart';
import '../../../client/watch_client.dart';
import '../../../core/transfer_manager.dart';
import '../../services/download_folder_validation.dart';
import '../../services/friendly_error_message.dart';
import '../../widgets/file_manager/breadcrumb_bar.dart';
import '../../widgets/file_manager/dialogs/confirm_delete_dialog.dart';
import '../../widgets/file_manager/dialogs/conflict_dialog.dart';
import '../../widgets/file_manager/dialogs/create_folder_dialog.dart';
import '../../widgets/file_manager/dialogs/properties_dialog.dart';
import '../../widgets/file_manager/drop_upload_region.dart';
import '../../widgets/file_manager/dialogs/rename_dialog.dart';
import '../../widgets/file_manager/file_grid_tile.dart';
import '../../widgets/file_manager/file_list_tile.dart';
import '../../widgets/file_manager/sort_menu.dart';
import '../../widgets/file_manager/upload_progress_overlay.dart';
import '../../widgets/file_manager/view_mode_toggle.dart';
import 'desktop_pdf_opener.dart';
import 'file_preview_screen.dart';
import 'image_preview_screen.dart';
import 'pdf_preview_screen.dart';
import 'text_editor_screen.dart';

part 'file_manager_screen_state.dart';
part 'file_manager_screen_opening.dart';
part 'file_manager_screen_drag_drop.dart';

// ─── Keyboard shortcut intents ───────────────────────────────────────────────

class _CopyIntent extends Intent {
  const _CopyIntent();
}

class _CutIntent extends Intent {
  const _CutIntent();
}

class _PasteIntent extends Intent {
  const _PasteIntent();
}

class _SelectAllIntent extends Intent {
  const _SelectAllIntent();
}

class _DeleteIntent extends Intent {
  const _DeleteIntent();
}

class _RenameIntent extends Intent {
  const _RenameIntent();
}

class _NewFolderIntent extends Intent {
  const _NewFolderIntent();
}

class _NavUpIntent extends Intent {
  const _NavUpIntent();
}

class _OpenIntent extends Intent {
  const _OpenIntent();
}

// ─── FileManagerScreen ───────────────────────────────────────────────────────

class FileManagerScreen extends StatefulWidget {
  final FileClient client;
  final String alias;
  final String role;
  final String initialPath;
  final void Function(String kind, FileEntry entry)? onOpenFile;

  /// Optional factory to create a [WatchClient] for a given [watchPath].
  ///
  /// Pass `watcherFactory: null` in tests to disable real-time watching.
  final WatchClient? Function(String watchPath)? watcherFactory;
  final Future<String?> Function() directoryPicker;

  static const _unsetFactory = Object();

  FileManagerScreen({
    super.key,
    required this.client,
    required this.alias,
    required this.role,
    this.initialPath = '/',
    this.onOpenFile,
    Future<String?> Function()? directoryPicker,
    Object? watcherFactory = _unsetFactory,
  }) : directoryPicker = directoryPicker ?? FilePicker.getDirectoryPath,
       watcherFactory = watcherFactory == _unsetFactory
           ? ((watchPath) => WatchClient(
               baseUrl: client.baseUrl,
               sessionToken: client.sessionToken,
               alias: alias,
               watchPath: watchPath,
             ))
           : watcherFactory as WatchClient? Function(String)?;

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _DownloadControlState {
  bool paused = false;
  bool aborted = false;
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  static const _downloadFolderPrefKey = 'guest.downloadFolder';
  static const _roleRefreshInterval = Duration(seconds: 2);

  late final FileManagerState _state;
  String? _downloadFolder;
  late String _sessionRole;

  bool _searchActive = false;
  final TextEditingController _searchController = TextEditingController();
  Timer? _roleRefreshTimer;
  Timer? _watchReloadDebounce;

  WatchClient? _watcher;
  final DesktopPdfOpener _desktopPdfOpener = DesktopPdfOpener();
  final Map<String, UploadProgressItem> _uploadProgress = {};
  final Map<String, UploadProgressItem> _downloadProgress = {};
  final Map<String, _DownloadControlState> _downloadControls = {};
  final Set<Timer> _downloadCleanupTimers = <Timer>{};
  int _roleRefreshFailures = 0;
  static const _maxRoleRefreshFailures = 3;

  /// Anchor path for Shift+click range selection on desktop.
  String? _lastSelectedPath;

  String get _normalizedRole => _sessionRole.trim().toLowerCase();

  bool get _canWrite =>
      _normalizedRole == 'editor' || _normalizedRole == 'owner';
  bool get _canDelete => _normalizedRole == 'owner';
  bool get _isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _state = FileManagerState(initialPath: widget.initialPath);
    _sessionRole = widget.role;
    _state.addListener(_onStateChanged);
    _startRoleRefresh();
    _loadDownloadFolder();
    _load();
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChanged);
    _state.dispose();
    _searchController.dispose();
    _roleRefreshTimer?.cancel();
    _watchReloadDebounce?.cancel();
    for (final timer in _downloadCleanupTimers) {
      timer.cancel();
    }
    _downloadCleanupTimers.clear();
    _watcher?.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _startRoleRefresh() {
    _roleRefreshTimer?.cancel();
    _roleRefreshFailures = 0;
    _roleRefreshTimer = Timer.periodic(
      _roleRefreshInterval,
      (_) => _refreshSessionRole(),
    );
  }

  Future<void> _refreshSessionRole() async {
    final result = await widget.client.getSessionRole();
    if (!mounted) return;
    if (result.isErr) {
      _roleRefreshFailures++;
      if (_roleRefreshFailures >= _maxRoleRefreshFailures) {
        // Token has likely expired or the endpoint is unavailable.
        // Stop polling to avoid spamming the host's server with failed requests.
        _roleRefreshTimer?.cancel();
        _roleRefreshTimer = null;
      }
      return;
    }

    _roleRefreshFailures = 0;
    final nextRole = result.unwrap;
    if (nextRole == _sessionRole) return;

    setState(() {
      _sessionRole = nextRole;
    });
  }

  // ─── Settings ─────────────────────────────────────────────────────────────

  String _defaultDownloadFolder() {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    if (home.isEmpty) return 'Downloads/OpenFoldr';
    return p.join(home, 'Downloads', 'OpenFoldr');
  }

  Future<void> _loadDownloadFolder() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _downloadFolder =
          prefs.getString(_downloadFolderPrefKey) ?? _defaultDownloadFolder();
    });
  }

  Future<void> _saveDownloadFolder(String folder) async {
    final normalized = folder.trim();
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_downloadFolderPrefKey, normalized);
    if (!mounted) return;
    setState(() => _downloadFolder = normalized);
  }

  Future<String?> _promptForAnotherDownloadFolder({
    required String currentFolder,
    required String reason,
  }) async {
    var selectedFolder = currentFolder;
    final shouldUse = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Download folder unavailable'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(reason),
              const SizedBox(height: 8),
              Text(
                selectedFolder,
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () async {
                  final selected = await widget.directoryPicker();
                  if (selected == null || selected.trim().isEmpty) return;
                  setDialogState(() {
                    selectedFolder = selected.trim();
                  });
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose another folder'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel download'),
            ),
            FilledButton(
              onPressed: selectedFolder.trim().isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('Use this folder'),
            ),
          ],
        ),
      ),
    );

    if (shouldUse != true) return null;
    final nextFolder = selectedFolder.trim();
    if (nextFolder.isEmpty) return null;
    await _saveDownloadFolder(nextFolder);
    return nextFolder;
  }

  Future<String?> _resolveWritableDownloadFolder() async {
    var folder = (_downloadFolder ?? _defaultDownloadFolder()).trim();
    while (mounted) {
      final issue = await validateDownloadFolderForWrite(folder);
      if (issue == null) return folder;

      final replacement = await _promptForAnotherDownloadFolder(
        currentFolder: folder,
        reason: issue,
      );
      if (replacement == null) return null;
      folder = replacement;
    }
    return null;
  }

  // ─── Navigation ────────────────────────────────────────────────────────────

  Future<bool> _onWillPop() async {
    if (_searchActive) {
      _closeSearch();
      return false;
    }
    if (_state.multiSelectMode) {
      _state.clearSelection();
      return false;
    }
    return !_state.popPath();
  }

  // ─── Load directory ────────────────────────────────────────────────────────

  Future<void> _load() async {
    _state.setLoading();
    final result = await widget.client.listEntries(
      widget.alias,
      _state.currentPath,
    );
    if (!mounted) return;
    if (result.isOk) {
      _state.setEntries(result.unwrap);
      _startWatcher();
    } else if (result.errorCode == 'UNAUTHORIZED') {
      // Session token expired — pop back so ExplorerScreen can re-pair.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Reconnecting…')),
      );
      Navigator.of(context).pop();
    } else {
      _state.setError(
        friendlyErrorMessage(
          code: result.errorCode,
          fallbackMessage: result.errorMessage,
          operation: 'load this folder',
        ),
      );
      _startWatcher();
    }
  }

  /// Refreshes the current directory entries without switching to loading UI.
  ///
  /// Used after write actions so the list updates in place and keeps scroll
  /// position stable.
  Future<void> _refreshEntriesInPlace() async {
    final result = await widget.client.listEntries(
      widget.alias,
      _state.currentPath,
    );
    if (!mounted) return;
    if (result.isOk) {
      _state.setEntries(result.unwrap);
    } else if (result.errorCode == 'UNAUTHORIZED') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session expired. Reconnecting…')),
      );
      Navigator.of(context).pop();
    } else {
      _showResultError(result, operation: 'refresh this folder');
    }
  }

  /// (Re)starts the [WatchClient] for the current directory.
  ///
  /// Disposes any existing watcher before creating a new one so navigation
  /// between directories always watches the right path.
  void _startWatcher() {
    _watcher?.dispose();
    final newWatcher = widget.watcherFactory?.call(_state.currentPath);
    if (newWatcher == null) return;
    _watcher = newWatcher;
    _watcher!.events.listen((event) {
      // Burst file events are common; coalesce them into a single reload.
      if (!mounted) return;
      _watchReloadDebounce?.cancel();
      _watchReloadDebounce = Timer(const Duration(milliseconds: 180), () {
        if (mounted) _refreshEntriesInPlace();
      });
    });
    _watcher!.connect();
  }

  // ─── Upload ────────────────────────────────────────────────────────────────

  Future<void> _uploadNewFile() async {
    final picked = await FilePicker.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final remotePath =
        '${_state.currentPath == '/' ? '' : _state.currentPath}/${file.name}';
    await _performUpload(remotePath, bytes, file.name);
  }

  /// Performs file upload with conflict handling.
  /// 
  /// If the file already exists, shows a dialog asking the user to:
  /// - Overwrite the existing file
  /// - Rename the file
  /// - Cancel the upload
  Future<void> _performUpload(
    String remotePath,
    Uint8List bytes,
    String fileName, {
    bool forceOverwrite = false,
  }) async {
    final result = await widget.client.uploadFile(
      widget.alias,
      remotePath,
      bytes,
      ifMatch: forceOverwrite ? '*' : null,
    );
    if (!mounted) return;

    if (result.isOk) {
      await _refreshEntriesInPlace();
      return;
    }

    // Handle conflict: file already exists
    if (result.errorCode == 'PRECONDITION_REQUIRED') {
      final conflictResult = await showUploadConflictDialog(
        context,
        fileName: fileName,
        allowApplyToAll: false,
      );

      if (!mounted) return;
      if (conflictResult == null ||
          conflictResult.resolution == UploadConflictResolution.cancel) {
        return;
      }

      if (conflictResult.resolution == UploadConflictResolution.overwrite) {
        // Retry with force-overwrite
        await _performUpload(remotePath, bytes, fileName, forceOverwrite: true);
        return;
      }

      if (conflictResult.resolution == UploadConflictResolution.rename) {
        // Generate a new name with a timestamp suffix
        final ext = fileName.contains('.')
            ? fileName.substring(fileName.lastIndexOf('.'))
            : '';
        final base = ext.isNotEmpty
            ? fileName.substring(0, fileName.lastIndexOf('.'))
            : fileName;
        final newFileName =
            '${base}_${DateTime.now().millisecondsSinceEpoch}$ext';
        final newRemotePath =
          '${remotePath.substring(0, remotePath.lastIndexOf('/'))}/$newFileName';
        await _performUpload(newRemotePath, bytes, newFileName);
        return;
      }
    } else {
      _showResultError(result, operation: 'upload this file');
    }
  }


  Future<void> _doPut(
    String remotePath,
    Uint8List bytes, {
    required String ifMatch,
  }) async {
    final result = await widget.client.uploadFile(
      widget.alias,
      remotePath,
      bytes,
      ifMatch: ifMatch,
    );
    if (!mounted) return;
    if (result.isOk) {
      await _refreshEntriesInPlace();
      return;
    }
    if (result.errorCode == 'VERSION_CONFLICT') {
      final metaResult = await widget.client.getMetadata(
        widget.alias,
        remotePath,
      );
      final latestToken = metaResult.isOk
          ? metaResult.unwrap.versionToken
          : '*';
      _showConflictDialog(remotePath, bytes, latestToken);
      return;
    }
    _showResultError(result, operation: 'save this file');
  }

  // ─── Download ──────────────────────────────────────────────────────────────

  void _updateDownloadProgressItem(
    String remotePath,
    String name,
    double progress, {
    bool complete = false,
    String? error,
  }) {
    final control = _downloadControls[remotePath];
    _downloadProgress[remotePath] = UploadProgressItem(
      name: name,
      progress: progress,
      complete: complete,
      paused: control?.paused ?? false,
      error: error,
      onPause:
          (control != null && !complete && error == null && !control.paused)
          ? () {
              setState(() {
                control.paused = true;
                _updateDownloadProgressItem(
                  remotePath,
                  name,
                  progress,
                  complete: complete,
                );
              });
            }
          : null,
      onResume:
          (control != null && !complete && error == null && control.paused)
          ? () {
              setState(() {
                control.paused = false;
                _updateDownloadProgressItem(
                  remotePath,
                  name,
                  progress,
                  complete: complete,
                );
              });
            }
          : null,
      onAbort: (control != null && !complete)
          ? () {
              setState(() {
                control.aborted = true;
              });
            }
          : null,
    );
  }

  Future<void> _downloadFile(String remotePath, String name) async {
    final downloadManager = ResumableDownloadManager(
      base: widget.client.baseUrl,
      sessionToken: widget.client.sessionToken,
    );
    final control = _DownloadControlState();

    setState(() {
      _downloadControls[remotePath] = control;
      _updateDownloadProgressItem(remotePath, name, 0);
    });

    try {
      final bytes = await downloadManager.download(
        alias: widget.alias,
        remotePath: remotePath,
        isPaused: () => control.paused,
        isAborted: () => control.aborted,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _updateDownloadProgressItem(
              remotePath,
              name,
              progress.fraction,
              complete: progress.complete,
            );
          });
        },
      );
      if (!mounted) return;
      final fileName = p.basename(name.isNotEmpty ? name : remotePath);

      String? outputPath;
      while (mounted && outputPath == null) {
        final folder = await _resolveWritableDownloadFolder();
        if (folder == null) {
          if (!mounted) return;
          setState(() {
            _downloadProgress.remove(remotePath);
            _downloadControls.remove(remotePath);
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Download cancelled.')),
          );
          return;
        }

        final candidatePath = p.join(folder, fileName);
        try {
          await File(candidatePath).writeAsBytes(bytes, flush: true);
          outputPath = candidatePath;
        } on FileSystemException catch (e) {
          final replacement = await _promptForAnotherDownloadFolder(
            currentFolder: folder,
            reason: e.osError?.message ??
                'OpenFoldr cannot write to this folder. Choose a writable folder.',
          );
          if (replacement == null) {
            if (!mounted) return;
            setState(() {
              _downloadProgress.remove(remotePath);
              _downloadControls.remove(remotePath);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Download cancelled.')),
            );
            return;
          }
        }
      }

      if (outputPath == null || !mounted) return;

      setState(() {
        _updateDownloadProgressItem(remotePath, name, 1, complete: true);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved to $outputPath')));
    } catch (e) {
      if (!mounted) return;
      if (e is TransferAbortedException) {
        setState(() {
          _downloadProgress.remove(remotePath);
          _downloadControls.remove(remotePath);
        });
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Download aborted')));
        return;
      }
      setState(() {
        _updateDownloadProgressItem(remotePath, name, 0, error: e.toString());
      });
      _showError('Download failed: $e');
    } finally {
      downloadManager.dispose();
      if (mounted) {
        late final Timer cleanupTimer;
        cleanupTimer = Timer(const Duration(seconds: 2), () {
          _downloadCleanupTimers.remove(cleanupTimer);
          if (!mounted) return;
          setState(() {
            _downloadProgress.remove(remotePath);
            _downloadControls.remove(remotePath);
          });
        });
        _downloadCleanupTimers.add(cleanupTimer);
      }
    }
  }

  Future<void> _openDesktopPdf(FileEntry entry) async {
    final result = await widget.client.downloadFile(widget.alias, entry.path);
    if (!mounted) return;

    if (result.isErr) {
      _showResultError(result, operation: 'open this file');
      return;
    }

    try {
      await _desktopPdfOpener.openPdf(result.unwrap, entry.name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Opened PDF in the system viewer.')),
      );
    } catch (_) {
      if (!mounted) return;
      _showError('Could not open PDF file.');
    }
  }

  Future<void> _downloadSelected() async {
    final byPath = {for (final e in _state.entries) e.path: e};
    final selected = _state.selectedPaths
        .map((path) => byPath[path])
        .whereType<FileEntry>()
        .toList(growable: false);

    if (selected.isEmpty) return;

    final files = selected.where((e) => e.isFile).toList(growable: false);
    final skippedDirs = selected.length - files.length;

    if (files.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected items are folders. Folder download is not supported yet.'),
        ),
      );
      return;
    }

    _state.clearSelection();

    if (skippedDirs > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Downloading ${files.length} file(s). Skipped $skippedDirs folder(s).',
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloading ${files.length} file(s)...')),
      );
    }

    for (final file in files) {
      if (!mounted) return;
      await _downloadFile(file.path, file.name);
    }
  }

  Future<bool> _confirmBinaryDownload(FileEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Download file?'),
        content: Text(
          'This file cannot be previewed. Download "${entry.name}" (${_formatSize(entry.size)})?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Download'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  // ─── Delete ────────────────────────────────────────────────────────────────

  Future<void> _deleteEntry(String remotePath, String name) async {
    final confirmed = await showConfirmDeleteDialog(
      context,
      itemCount: 1,
      itemName: name,
    );
    if (!confirmed) return;
    final result = await widget.client.deleteItem(widget.alias, remotePath);
    if (!mounted) return;
    if (result.isOk) {
      _state.removeEntry(remotePath);
      _lastSelectedPath = null;
    } else {
      _showResultError(result, operation: 'delete this item');
    }
  }

  // ─── Rename ────────────────────────────────────────────────────────────────

  Future<void> _renameEntry(FileEntry entry) async {
    final newName = await showRenameDialog(context, currentName: entry.name);
    if (newName == null || newName == entry.name) return;

    final dir = entry.path.contains('/')
        ? entry.path.substring(0, entry.path.lastIndexOf('/'))
        : '';
    final newPath = dir.isEmpty ? '/$newName' : '$dir/$newName';

    final result = await widget.client.rename(
      widget.alias,
      entry.path,
      newPath,
    );
    if (!mounted) return;
    if (result.isOk) {
      _state.renameEntry(entry.path, newPath);
      if (_lastSelectedPath == entry.path) {
        _lastSelectedPath = newPath;
      }
    } else {
      _showResultError(result, operation: 'rename this item');
    }
  }

  // ─── Conflict dialog (upload version conflict) ──────────────────────────────

  void _showConflictDialog(
    String remotePath,
    Uint8List bytes,
    String latestToken,
  ) {
    // The upload-version conflict reuses the generic conflict dialog shape
    // but maps actions to the upload retry flow.
    showDialog<ConflictResolution?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Version Conflict'),
        content: const Text(
          'This file was modified by another client. '
          'How would you like to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, ConflictResolution.skip),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ConflictResolution.keepBoth),
            child: const Text('Save as Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ConflictResolution.replace),
            child: const Text('Retry with Latest'),
          ),
          if (_canDelete)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, ConflictResolution.replace),
              child: const Text('Force Overwrite'),
            ),
        ],
      ),
    ).then((resolution) async {
      if (resolution == null || resolution == ConflictResolution.skip) return;
      if (resolution == ConflictResolution.keepBoth) {
        final ext = remotePath.contains('.')
            ? remotePath.substring(remotePath.lastIndexOf('.'))
            : '';
        final base = ext.isNotEmpty
            ? remotePath.substring(0, remotePath.lastIndexOf('.'))
            : remotePath;
        final copyPath =
            '${base}_copy_${DateTime.now().millisecondsSinceEpoch}$ext';
        await _doPut(copyPath, bytes, ifMatch: '');
      } else {
        await _doPut(remotePath, bytes, ifMatch: latestToken);
      }
    });
  }

  // ─── Create folder ─────────────────────────────────────────────────────────

  Future<void> _createFile() async {
    final name = await _showCreateFileDialog();
    if (name == null || name.isEmpty) return;
    final path = '${_state.currentPath == '/' ? '' : _state.currentPath}/$name';
    final result = await widget.client.uploadFile(
      widget.alias,
      path,
      Uint8List(0),
    );
    if (!mounted) return;
    if (result.isOk) {
      await _refreshEntriesInPlace();
    } else {
      _showResultError(result, operation: 'create this file');
    }
  }

  Future<String?> _showCreateFileDialog() {
    final controller = TextEditingController();

    bool isValid(String v) =>
        v.isNotEmpty && !v.contains('/') && v != '..' && v != '.';

    return showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('New File'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'File name',
              border: const OutlineInputBorder(),
              errorText: controller.text.isNotEmpty && !isValid(controller.text)
                  ? 'Name cannot contain / or be . or ..'
                  : null,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (v) {
              final name = v.trim();
              if (isValid(name)) Navigator.pop(ctx, name);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: isValid(controller.text.trim())
                  ? () => Navigator.pop(ctx, controller.text.trim())
                  : null,
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createFolder() async {
    final name = await showCreateFolderDialog(context);
    if (name == null || name.isEmpty) return;
    final path = '${_state.currentPath == '/' ? '' : _state.currentPath}/$name';
    final result = await widget.client.mkdir(widget.alias, path);
    if (!mounted) return;
    if (result.isOk) {
      await _refreshEntriesInPlace();
    } else {
      _showResultError(result, operation: 'create this folder');
    }
  }

  // ─── File actions bottom sheet ─────────────────────────────────────────────

  // ─── Settings dialog ───────────────────────────────────────────────────────

  Future<void> _showSettingsDialog() async {
    final initial = _downloadFolder ?? _defaultDownloadFolder();
    final controller = TextEditingController(text: initial);
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Download folder'),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '~/Downloads/OpenFoldr',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  final selected = await widget.directoryPicker();
                  if (selected != null && selected.isNotEmpty) {
                    controller.text = selected;
                  }
                },
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose Folder'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (shouldSave == true) {
      await _saveDownloadFolder(controller.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download folder set to ${controller.text.trim()}'),
        ),
      );
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showResultError(Result<dynamic> result, {required String operation}) {
    if (!result.isErr) return;
    _showError(
      friendlyErrorMessage(
        code: result.errorCode,
        fallbackMessage: result.errorMessage,
        operation: operation,
      ),
    );
  }

  void _openSearch() {
    setState(() => _searchActive = true);
  }

  void _closeSearch() {
    _searchController.clear();
    _state.clearSearch();
    setState(() => _searchActive = false);
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.keyC, control: true):
          const _CopyIntent(),
      const SingleActivator(LogicalKeyboardKey.keyX, control: true):
          const _CutIntent(),
      const SingleActivator(LogicalKeyboardKey.keyV, control: true):
          const _PasteIntent(),
      const SingleActivator(LogicalKeyboardKey.keyA, control: true):
          const _SelectAllIntent(),
      const SingleActivator(LogicalKeyboardKey.f2): const _RenameIntent(),
      const SingleActivator(LogicalKeyboardKey.keyN, control: true):
          const _NewFolderIntent(),
      const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
          const _NavUpIntent(),
      const SingleActivator(LogicalKeyboardKey.enter): const _OpenIntent(),
    };
    if (!_searchActive) {
      // Keep text-editing keys free for the search field when search is open.
      shortcuts[const SingleActivator(LogicalKeyboardKey.delete)] =
          const _DeleteIntent();
      shortcuts[const SingleActivator(LogicalKeyboardKey.backspace)] =
          const _NavUpIntent();
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final goBack = await _onWillPop();
        if (goBack && context.mounted) Navigator.pop(context);
        if (!goBack) await _load();
      },
      child: Shortcuts(
        shortcuts: shortcuts,
        child: Actions(
          actions: {
            _CopyIntent: CallbackAction<_CopyIntent>(
              onInvoke: (_) {
                if (_state.hasSelection && !_searchActive) {
                  _state.copySelected(widget.alias);
                  _state.clearSelection();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                }
                return null;
              },
            ),
            _CutIntent: CallbackAction<_CutIntent>(
              onInvoke: (_) {
                if (_state.hasSelection && _canWrite && !_searchActive) {
                  _state.cutSelected(widget.alias);
                  _state.clearSelection();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Cut to clipboard')),
                  );
                }
                return null;
              },
            ),
            _PasteIntent: CallbackAction<_PasteIntent>(
              onInvoke: (_) {
                if (_state.clipboard != null && _canWrite && !_searchActive) {
                  _paste();
                }
                return null;
              },
            ),
            _SelectAllIntent: CallbackAction<_SelectAllIntent>(
              onInvoke: (_) {
                if (!_searchActive) _state.selectAll();
                return null;
              },
            ),
            _DeleteIntent: CallbackAction<_DeleteIntent>(
              onInvoke: (_) {
                if (_state.hasSelection && _canDelete && !_searchActive) {
                  _deleteSelected();
                }
                return null;
              },
            ),
            _RenameIntent: CallbackAction<_RenameIntent>(
              onInvoke: (_) {
                if (_state.selectedPaths.length == 1 &&
                    _canWrite &&
                    !_searchActive) {
                  final path = _state.selectedPaths.first;
                  final entry = _state.entries
                      .where((e) => e.path == path)
                      .firstOrNull;
                  if (entry != null) _renameEntry(entry);
                }
                return null;
              },
            ),
            _NewFolderIntent: CallbackAction<_NewFolderIntent>(
              onInvoke: (_) {
                if (_canWrite && !_searchActive) _createFolder();
                return null;
              },
            ),
            _NavUpIntent: CallbackAction<_NavUpIntent>(
              onInvoke: (_) {
                // Don't intercept when a text field has focus (search bar).
                if (_searchActive) return null;
                if (_state.canGoUp) {
                  _state.popPath();
                  _state.clearSelection();
                  _load();
                }
                return null;
              },
            ),
            _OpenIntent: CallbackAction<_OpenIntent>(
              onInvoke: (_) {
                if (_state.selectedPaths.length == 1 && !_searchActive) {
                  final path = _state.selectedPaths.first;
                  final entry = _state.entries
                      .where((e) => e.path == path)
                      .firstOrNull;
                  if (entry != null) _handleTap(entry);
                }
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              appBar: _buildAppBar(),
              body: Column(
                children: [
                  BreadcrumbBar(
                    alias: widget.alias,
                    currentPath: _state.currentPath,
                    onDropPaths: _isDesktop && _canWrite
                        ? (paths, destination) =>
                              _moveDraggedPaths(paths, destination)
                        : null,
                    onNavigateTo: (path) async {
                      _state.navigateTo(path);
                      _state.clearSelection();
                      if (_searchActive) _closeSearch();
                      await _load();
                    },
                  ),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: DropUploadRegion(
                            enabled: _isDesktop && _canWrite,
                            onFilesDropped: _uploadDroppedFiles,
                            child: _buildBody(),
                          ),
                        ),
                        Positioned.fill(
                          child: IgnorePointer(
                            ignoring: false,
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    UploadProgressOverlay(
                                      items: _downloadProgress.values.toList(),
                                      title: 'Downloading files',
                                    ),
                                    const SizedBox(height: 8),
                                    UploadProgressOverlay(
                                      items: _uploadProgress.values.toList(),
                                      title: 'Uploading files',
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              floatingActionButton: _canWrite && !_state.multiSelectMode
                  ? FloatingActionButton(
                      tooltip: 'New',
                      onPressed: _showNewItemMenu,
                      child: const Icon(Icons.add),
                    )
                  : null,
              bottomNavigationBar: _state.hasSelection
                  ? _buildBottomBar()
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    if (_state.multiSelectMode) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            _state.clearSelection();
          },
        ),
        title: Text('${_state.selectedPaths.length} selected'),
        actions: [
          IconButton(
            icon: const Icon(Icons.select_all),
            tooltip: 'Select all',
            onPressed: _state.selectAll,
          ),
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: 'Download selected',
            onPressed: _downloadSelected,
          ),
          if (_canDelete)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              tooltip: 'Delete selected',
              onPressed: _deleteSelected,
            ),
        ],
      );
    }

    return AppBar(
      title: _searchActive
          ? TextField(
              controller: _searchController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Search…',
                border: InputBorder.none,
                isDense: true,
              ),
              onChanged: _state.setSearchQuery,
            )
          : Text(widget.alias),
      actions: [
        if (_searchActive)
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close search',
            onPressed: _closeSearch,
          )
        else ...[
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search',
            onPressed: _openSearch,
          ),
          ViewModeToggle(mode: _state.viewMode, onChanged: _state.setViewMode),
          SortMenu(
            sortBy: _state.sortBy,
            sortOrder: _state.sortOrder,
            onChanged: _state.setSortBy,
          ),
          if (_canWrite)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'New item',
              onPressed: _showNewItemMenu,
            ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: _showSettingsDialog,
          ),
        ],
      ],
    );
  }

  Widget _buildBody() {
    if (_state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_state.error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_state.error!),
            const SizedBox(height: 16),
            FilledButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    // Tap on the background (empty space) exits multi-select mode.
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _state.multiSelectMode ? _state.clearSelection : null,
      child: _buildScrollBody(),
    );
  }

  Widget _buildScrollBody() {
    final visible = _state.filteredEntries;

    if (visible.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 120),
            Center(
              child: Text(
                _state.searchQuery.isNotEmpty
                    ? 'No results for "${_state.searchQuery}"'
                    : 'Empty folder',
              ),
            ),
          ],
        ),
      );
    }

    if (_state.viewMode == ViewMode.grid) {
      return RefreshIndicator(
        onRefresh: _load,
        child: GridView.builder(
          padding: const EdgeInsets.all(8),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 140,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
            childAspectRatio: 0.85,
          ),
          itemCount: visible.length,
          itemBuilder: (_, i) {
            final entry = visible[i];
            return FileGridTile(
              client: widget.client,
              alias: widget.alias,
              entry: entry,
              selected: _state.selectedPaths.contains(entry.path),
              multiSelectMode: _state.multiSelectMode,
              draggablePaths: _isDesktop && _canWrite
                  ? _dragPayloadForEntry(entry)
                  : null,
              onDragStarted: _isDesktop && _canWrite
                  ? () => _handleDragStarted(entry)
                  : null,
              onDragCompleted: _isDesktop && _canWrite
                  ? _handleDragCompleted
                  : null,
              onDropPaths: entry.isDirectory && _isDesktop && _canWrite
                  ? (paths) => _moveDraggedPaths(paths, entry.path)
                  : null,
              onTap: _isDesktop
                  ? () => _handleDesktopClick(entry)
                  : () => _handleTap(entry),
              onDoubleTap: _isDesktop ? () => _openEntry(entry) : null,
              onLongPress: _isDesktop
                  ? null
                  : () => _state.toggleSelect(entry.path),
            );
          },
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: visible.length,
        itemBuilder: (_, i) {
          final entry = visible[i];
          return FileListTile(
            client: widget.client,
            alias: widget.alias,
            entry: entry,
            selected: _state.selectedPaths.contains(entry.path),
            multiSelectMode: _state.multiSelectMode,
            draggablePaths: _isDesktop && _canWrite
                ? _dragPayloadForEntry(entry)
                : null,
            onDragStarted: _isDesktop && _canWrite
                ? () => _handleDragStarted(entry)
                : null,
            onDragCompleted: _isDesktop && _canWrite
                ? _handleDragCompleted
                : null,
            onDropPaths: entry.isDirectory && _isDesktop && _canWrite
                ? (paths) => _moveDraggedPaths(paths, entry.path)
                : null,
            onTap: _isDesktop
                ? () => _handleDesktopClick(entry)
                : () => _handleTap(entry),
            onDoubleTap: _isDesktop ? () => _openEntry(entry) : null,
            onLongPress: _isDesktop
                ? null
                : () => _state.toggleSelect(entry.path),
          );
        },
      ),
    );
  }


  Widget _buildBottomBar() {
    final byPath = {for (final e in _state.entries) e.path: e};
    final selected = _state.selectedPaths
        .map((path) => byPath[path])
        .whereType<FileEntry>()
        .toList(growable: false);

    final isSingleSelection = selected.length == 1;
    final selectedEntry = isSingleSelection ? selected.first : null;
    final isFile = selectedEntry?.isFile ?? false;
    final isDir = selectedEntry?.isDirectory ?? false;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Preview (single file only)
              if (isSingleSelection && isFile)
                IconButton(
                  icon: const Icon(Icons.preview),
                  tooltip: 'Preview',
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FilePreviewScreen(
                          base: widget.client.baseUrl,
                          sessionToken: widget.client.sessionToken,
                          alias: widget.alias,
                          remotePath: selectedEntry!.path,
                          fileName: selectedEntry.name,
                          fileSize: selectedEntry.size,
                        ),
                      ),
                    );
                    _state.clearSelection();
                  },
                ),
              // Download selected
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Download selected',
                onPressed: _downloadSelected,
              ),
              // Copy
              IconButton(
                icon: const Icon(Icons.copy),
                tooltip: 'Copy',
                onPressed: () {
                  _state.copySelected(widget.alias);
                  _state.clearSelection();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied to clipboard')),
                  );
                },
              ),
              // Cut
              IconButton(
                icon: const Icon(Icons.cut),
                tooltip: 'Cut',
                onPressed: _canWrite
                    ? () {
                        _state.cutSelected(widget.alias);
                        _state.clearSelection();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Cut to clipboard')),
                        );
                      }
                    : null,
              ),
              // Paste
              if (_state.clipboard != null && _canWrite)
                IconButton(
                  icon: const Icon(Icons.paste),
                  tooltip: 'Paste',
                  onPressed: _paste,
                ),
              // Rename (single item, can write)
              if (isSingleSelection && _canWrite)
                IconButton(
                  icon: const Icon(Icons.drive_file_rename_outline),
                  tooltip: 'Rename',
                  onPressed: () {
                    _renameEntry(selectedEntry!);
                    _state.clearSelection();
                  },
                ),
              // Properties (single item only)
              if (isSingleSelection)
                IconButton(
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'Properties',
                  onPressed: () {
                    showPropertiesDialog(context, entry: selectedEntry!);
                    _state.clearSelection();
                  },
                ),
              // Delete
              if (_canDelete)
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: 'Delete selected',
                  onPressed: _deleteSelected,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _paste() async {
    final clip = _state.clipboard;
    if (clip == null) return;
    final destination = _state.currentPath;

    Result<List<BatchResult>> result;
    if (clip.operation == 'copy') {
      result = await widget.client.batchCopy(widget.alias, clip.items, destination);
    } else {
      result = await widget.client.batchMove(widget.alias, clip.items, destination);
    }
    if (!mounted) return;

    if (result.isErr) {
      _showResultError(
        result,
        operation: clip.operation == 'copy' ? 'copy selected items' : 'move selected items',
      );
      return;
    }

    _showBatchFailures(
      result.unwrap,
      operation: clip.operation == 'copy' ? 'copy selected items' : 'move selected items',
    );

    if (clip.operation == 'cut') _state.clearClipboard();
    _state.clearSelection();
    await _refreshEntriesInPlace();
  }

  Future<void> _deleteSelected() async {
    final count = _state.selectedPaths.length;
    final confirmed = await showConfirmDeleteDialog(context, itemCount: count);
    if (!confirmed) return;

    final result = await widget.client.batchDelete(
      widget.alias,
      _state.selectedPaths.toList(),
    );
    if (!mounted) return;

    if (result.isErr) {
      _showResultError(result, operation: 'delete selected items');
      return;
    }

    _showBatchFailures(result.unwrap, operation: 'delete selected items');

    _state.clearSelection();
    await _refreshEntriesInPlace();
  }

  void _showBatchFailures(List<BatchResult> results, {required String operation}) {
    final failures = results.where((item) => !item.isSuccess).toList(growable: false);
    if (failures.isEmpty) return;

    final first = failures.first;
    final message = friendlyErrorMessage(
      code: _errorCodeFromBatchFailure(first),
      fallbackMessage: first.message,
      operation: operation,
    );

    if (failures.length == 1) {
      _showError(message);
      return;
    }

    _showError('$message (${failures.length} items failed)');
  }

  String _errorCodeFromBatchFailure(BatchResult result) {
    final details = result.message.toLowerCase();
    if (details.contains('permission denied') ||
        details.contains('access is denied') ||
        details.contains('operation not permitted') ||
        details.contains('read-only file system')) {
      return 'PERMISSION_DENIED';
    }

    if (result.status == 400) return 'INVALID_ARGUMENT';
    if (result.status == 403) return 'FORBIDDEN';
    if (result.status == 404) return 'NOT_FOUND';
    if (result.status == 409) return 'ALREADY_EXISTS';
    if (result.status >= 500) return 'SERVER_ERROR';
    return 'SERVER_ERROR';
  }

  void _showNewItemMenu() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('New file'),
              onTap: () {
                Navigator.pop(ctx);
                _createFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('Upload file'),
              onTap: () {
                Navigator.pop(ctx);
                _uploadNewFile();
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder),
              title: const Text('New folder'),
              onTap: () {
                Navigator.pop(ctx);
                _createFolder();
              },
            ),
          ],
        ),
      ),
    );
  }

}
