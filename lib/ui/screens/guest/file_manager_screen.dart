import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../client/file_client.dart';
import '../../../client/watch_client.dart';
import '../../../core/transfer_manager.dart';
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
import 'file_preview_screen.dart';
import 'image_preview_screen.dart';
import 'pdf_preview_screen.dart';
import 'text_editor_screen.dart';

// ─── State model ────────────────────────────────────────────────────────────

class ClipboardState {
  final String operation; // 'copy' or 'cut'
  final List<String> items;
  final String sourceAlias;

  const ClipboardState({
    required this.operation,
    required this.items,
    required this.sourceAlias,
  });
}

class FileManagerState extends ChangeNotifier {
  final List<String> _pathStack;
  List<FileEntry> entries = [];
  SortField sortBy = SortField.name;
  SortOrder sortOrder = SortOrder.asc;
  ViewMode viewMode = ViewMode.list;
  final Set<String> selectedPaths = {};
  ClipboardState? clipboard;
  bool isLoading = true;
  String? error;

  FileManagerState({String initialPath = '/'})
      : _pathStack = [initialPath];

  String get currentPath => _pathStack.last;
  bool get canGoUp => _pathStack.length > 1;

  void pushPath(String path) {
    _pathStack.add(path);
    _searchQuery = '';
    notifyListeners();
  }

  bool popPath() {
    if (_pathStack.length <= 1) return false;
    _pathStack.removeLast();
    _searchQuery = '';
    notifyListeners();
    return true;
  }

  void navigateTo(String path) {
    // Navigate to a specific ancestor path: trim the stack to that path.
    final idx = _pathStack.lastIndexOf(path);
    if (idx >= 0) {
      _pathStack.removeRange(idx + 1, _pathStack.length);
    } else {
      _pathStack
        ..clear()
        ..add(path);
    }
    _searchQuery = '';
    notifyListeners();
  }

  void setEntries(List<FileEntry> newEntries) {
    entries = _sortedEntries(newEntries);
    isLoading = false;
    error = null;
    notifyListeners();
  }

  void setError(String msg) {
    error = msg;
    isLoading = false;
    notifyListeners();
  }

  void setLoading() {
    isLoading = true;
    error = null;
    notifyListeners();
  }

  void setSortBy(SortField field, SortOrder order) {
    sortBy = field;
    sortOrder = order;
    entries = _sortedEntries(entries);
    notifyListeners();
  }

  void setViewMode(ViewMode mode) {
    viewMode = mode;
    notifyListeners();
  }

  void toggleSelect(String path) {
    if (!selectedPaths.remove(path)) selectedPaths.add(path);
    notifyListeners();
  }

  void clearSelection() {
    selectedPaths.clear();
    notifyListeners();
  }

  void selectAll() {
    selectedPaths
      ..clear()
      ..addAll(entries.map((e) => e.path));
    notifyListeners();
  }

  bool get hasSelection => selectedPaths.isNotEmpty;
  bool get multiSelectMode => selectedPaths.isNotEmpty;

  // ─── Search ─────────────────────────────────────────────────────────────────

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  void setSearchQuery(String query) {
    _searchQuery = query.toLowerCase().trim();
    notifyListeners();
  }

  void clearSearch() {
    _searchQuery = '';
    notifyListeners();
  }

  List<FileEntry> get filteredEntries {
    if (_searchQuery.isEmpty) return entries;
    return entries
        .where((e) => e.name.toLowerCase().contains(_searchQuery))
        .toList();
  }

  void copySelected(String alias) {
    clipboard = ClipboardState(
      operation: 'copy',
      items: List.unmodifiable(selectedPaths),
      sourceAlias: alias,
    );
    notifyListeners();
  }

  void cutSelected(String alias) {
    clipboard = ClipboardState(
      operation: 'cut',
      items: List.unmodifiable(selectedPaths),
      sourceAlias: alias,
    );
    notifyListeners();
  }

  void clearClipboard() {
    clipboard = null;
    notifyListeners();
  }

  List<FileEntry> _sortedEntries(List<FileEntry> src) {
    final dirs = src.where((e) => e.isDirectory).toList();
    final files = src.where((e) => e.isFile).toList();

    int Function(FileEntry, FileEntry) cmp = switch (sortBy) {
      SortField.name => (a, b) => a.name.compareTo(b.name),
      SortField.size => (a, b) => a.size.compareTo(b.size),
      SortField.date => (a, b) => a.modifiedAt.compareTo(b.modifiedAt),
      SortField.type => (a, b) {
          final extA = a.name.contains('.')
              ? a.name.substring(a.name.lastIndexOf('.'))
              : '';
          final extB = b.name.contains('.')
              ? b.name.substring(b.name.lastIndexOf('.'))
              : '';
          final ext = extA.compareTo(extB);
          return ext != 0 ? ext : a.name.compareTo(b.name);
        },
    };

    if (sortOrder == SortOrder.desc) {
      final base = cmp;
      cmp = (a, b) => base(b, a);
    }

    dirs.sort(cmp);
    files.sort(cmp);
    return [...dirs, ...files];
  }
}

// ─── Keyboard shortcut intents ───────────────────────────────────────────────

class _CopyIntent extends Intent { const _CopyIntent(); }
class _CutIntent extends Intent { const _CutIntent(); }
class _PasteIntent extends Intent { const _PasteIntent(); }
class _SelectAllIntent extends Intent { const _SelectAllIntent(); }
class _DeleteIntent extends Intent { const _DeleteIntent(); }
class _RenameIntent extends Intent { const _RenameIntent(); }
class _NewFolderIntent extends Intent { const _NewFolderIntent(); }
class _NavUpIntent extends Intent { const _NavUpIntent(); }
class _OpenIntent extends Intent { const _OpenIntent(); }

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

  static const _unsetFactory = Object();

  FileManagerScreen({
    super.key,
    required this.client,
    required this.alias,
    required this.role,
    this.initialPath = '/',
    this.onOpenFile,
    Object? watcherFactory = _unsetFactory,
  }) : watcherFactory = watcherFactory == _unsetFactory
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

class _FileManagerScreenState extends State<FileManagerScreen> {
  static const _downloadFolderPrefKey = 'guest.downloadFolder';

  late final FileManagerState _state;
  String? _downloadFolder;

  bool _searchActive = false;
  final TextEditingController _searchController = TextEditingController();

  WatchClient? _watcher;
  final Map<String, UploadProgressItem> _uploadProgress = {};

  bool get _canWrite =>
      widget.role == 'editor' || widget.role == 'owner';
  bool get _canDelete => widget.role == 'owner';
  bool get _isDesktop =>
      Platform.isLinux || Platform.isWindows || Platform.isMacOS;

  @override
  void initState() {
    super.initState();
    _state = FileManagerState(initialPath: widget.initialPath);
    _state.addListener(_onStateChanged);
    _loadDownloadFolder();
    _load();
  }

  @override
  void dispose() {
    _state.removeListener(_onStateChanged);
    _state.dispose();
    _searchController.dispose();
    _watcher?.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  // ─── Settings ─────────────────────────────────────────────────────────────

  String _defaultDownloadFolder() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
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
    final result =
        await widget.client.listEntries(widget.alias, _state.currentPath);
    if (!mounted) return;
    if (result.isOk) {
      _state.setEntries(result.unwrap);
    } else {
      _state.setError(result.errorMessage);
    }
    _startWatcher();
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
      // On any filesystem change, reload the current directory listing.
      if (mounted) _load();
    });
    _watcher!.connect();
  }

  // ─── Upload ────────────────────────────────────────────────────────────────

  Future<void> _uploadNewFile() async {
    final picked =
        await FilePicker.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final file = picked.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;

    final remotePath =
        '${_state.currentPath == '/' ? '' : _state.currentPath}/${file.name}';
    final result = await widget.client.uploadFile(
        widget.alias, remotePath, bytes);
    if (!mounted) return;
    if (result.isOk) {
      await _load();
    } else {
      _showError(result.errorMessage);
    }
  }

  Future<void> _uploadNewVersion(String remotePath) async {
    final metaResult =
        await widget.client.getMetadata(widget.alias, remotePath);
    if (!mounted) return;
    if (metaResult.isErr) {
      _showError('Could not fetch file metadata');
      return;
    }
    final versionToken = metaResult.unwrap.versionToken;
    final picked =
        await FilePicker.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final bytes = picked.files.first.bytes;
    if (bytes == null) return;
    await _doPut(remotePath, bytes, ifMatch: versionToken);
  }

  Future<void> _doPut(String remotePath, Uint8List bytes,
      {required String ifMatch}) async {
    final result = await widget.client
        .uploadFile(widget.alias, remotePath, bytes, ifMatch: ifMatch);
    if (!mounted) return;
    if (result.isOk) {
      await _load();
      return;
    }
    if (result.errorCode == 'VERSION_CONFLICT') {
      final metaResult =
          await widget.client.getMetadata(widget.alias, remotePath);
      final latestToken =
          metaResult.isOk ? metaResult.unwrap.versionToken : '*';
      _showConflictDialog(remotePath, bytes, latestToken);
      return;
    }
    _showError(result.errorMessage);
  }

  // ─── Download ──────────────────────────────────────────────────────────────

  Future<void> _downloadFile(String remotePath, String name) async {
    final result =
        await widget.client.downloadFile(widget.alias, remotePath);
    if (!mounted) return;
    if (result.isOk) {
      final folder = _downloadFolder ?? _defaultDownloadFolder();
      final dir = Directory(folder);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      final fileName = p.basename(name.isNotEmpty ? name : remotePath);
      final outputPath = p.join(folder, fileName);
      await File(outputPath).writeAsBytes(result.unwrap, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to $outputPath')),
      );
    } else {
      _showError('Download failed: ${result.errorMessage}');
    }
  }

  // ─── Delete ────────────────────────────────────────────────────────────────

  Future<void> _deleteEntry(String remotePath, String name) async {
    final confirmed = await showConfirmDeleteDialog(
      context,
      itemCount: 1,
      itemName: name,
    );
    if (!confirmed) return;
    final result =
        await widget.client.deleteItem(widget.alias, remotePath);
    if (!mounted) return;
    if (result.isOk) {
      await _load();
    } else {
      _showError(result.errorMessage);
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

    final result =
        await widget.client.rename(widget.alias, entry.path, newPath);
    if (!mounted) return;
    if (result.isOk) {
      await _load();
    } else {
      _showError(result.errorMessage);
    }
  }

  // ─── Conflict dialog (upload version conflict) ──────────────────────────────

  void _showConflictDialog(
      String remotePath, Uint8List bytes, String latestToken) {
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
              child: const Text('Cancel')),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, ConflictResolution.keepBoth),
            child: const Text('Save as Copy'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, ConflictResolution.replace),
            child: const Text('Retry with Latest'),
          ),
          if (_canDelete)
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () =>
                  Navigator.pop(ctx, ConflictResolution.replace),
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
    final path =
        '${_state.currentPath == '/' ? '' : _state.currentPath}/$name';
    final result =
        await widget.client.uploadFile(widget.alias, path, Uint8List(0));
    if (!mounted) return;
    if (result.isOk) {
      await _load();
    } else {
      _showError(result.errorMessage);
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
              errorText:
                  controller.text.isNotEmpty && !isValid(controller.text)
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
    final path =
        '${_state.currentPath == '/' ? '' : _state.currentPath}/$name';
    final result = await widget.client.mkdir(widget.alias, path);
    if (!mounted) return;
    if (result.isOk) {
      await _load();
    } else {
      _showError(result.errorMessage);
    }
  }

  // ─── File actions bottom sheet ─────────────────────────────────────────────

  void _showFileActions(FileEntry entry) {
    final isDir = entry.isDirectory;
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!isDir)
              ListTile(
                leading: const Icon(Icons.preview),
                title: const Text('Preview'),
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FilePreviewScreen(
                        base: widget.client.baseUrl,
                        sessionToken: widget.client.sessionToken,
                        alias: widget.alias,
                        remotePath: entry.path,
                        fileName: entry.name,
                        fileSize: entry.size,
                      ),
                    ),
                  );
                },
              ),
            if (!isDir)
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Download'),
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadFile(entry.path, entry.name);
                },
              ),
            if (_canWrite && !isDir)
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Upload New Version'),
                onTap: () {
                  Navigator.pop(ctx);
                  _uploadNewVersion(entry.path);
                },
              ),
            if (_canWrite)
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('Rename'),
                onTap: () {
                  Navigator.pop(ctx);
                  _renameEntry(entry);
                },
              ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Properties'),
              onTap: () {
                Navigator.pop(ctx);
                showPropertiesDialog(context, entry: entry);
              },
            ),
            if (_canDelete)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text('Delete',
                    style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteEntry(entry.path, entry.name);
                },
              ),
          ],
        ),
      ),
    );
  }

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
                  final selected =
                      await FilePicker.getDirectoryPath();
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
              child: const Text('Cancel')),
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
            content: Text(
                'Download folder set to ${controller.text.trim()}')),
      );
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
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
                if (_state.hasSelection && !_searchActive) {
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
                if (_state.clipboard != null && !_searchActive) _paste();
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
                            ignoring: true,
                            child: UploadProgressOverlay(
                              items: _uploadProgress.values.toList(),
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
              bottomNavigationBar:
                  _state.hasSelection ? _buildBottomBar() : null,
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
          ViewModeToggle(
            mode: _state.viewMode,
            onChanged: _state.setViewMode,
          ),
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
              child: Text(_state.searchQuery.isNotEmpty
                  ? 'No results for "${_state.searchQuery}"'
                  : 'Empty folder'),
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
              entry: entry,
              selected: _state.selectedPaths.contains(entry.path),
              multiSelectMode: _state.multiSelectMode,
              draggablePaths:
                  _isDesktop && _canWrite ? _dragPayloadForEntry(entry) : null,
              onDragStarted: _isDesktop && _canWrite
                  ? () => _handleDragStarted(entry)
                  : null,
              onDragCompleted: _isDesktop && _canWrite
                  ? _handleDragCompleted
                  : null,
              onDropPaths: entry.isDirectory && _isDesktop && _canWrite
                  ? (paths) => _moveDraggedPaths(paths, entry.path)
                  : null,
              onTap: () => _handleTap(entry),
              onLongPress: () => _state.toggleSelect(entry.path),
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
            entry: entry,
            selected: _state.selectedPaths.contains(entry.path),
            multiSelectMode: _state.multiSelectMode,
            draggablePaths:
                _isDesktop && _canWrite ? _dragPayloadForEntry(entry) : null,
            onDragStarted: _isDesktop && _canWrite
                ? () => _handleDragStarted(entry)
                : null,
            onDragCompleted: _isDesktop && _canWrite
                ? _handleDragCompleted
                : null,
            onDropPaths: entry.isDirectory && _isDesktop && _canWrite
                ? (paths) => _moveDraggedPaths(paths, entry.path)
                : null,
            onTap: () => _handleTap(entry),
            onLongPress: () => _state.toggleSelect(entry.path),
            onMoreTap: () => _showFileActions(entry),
          );
        },
      ),
    );
  }

  void _handleTap(FileEntry entry) {
    if (_state.multiSelectMode) {
      _state.toggleSelect(entry.path);
      return;
    }
    if (entry.isDirectory) {
      _state.pushPath(entry.path);
      _state.clearSelection();
      if (_searchActive) _closeSearch();
      _load();
    } else {
      _openFile(entry);
    }
  }

  static bool _isTextFile(String name) {
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
        : '';
    const textExts = {
      'txt', 'md', 'markdown', 'json', 'yaml', 'yml', 'toml', 'csv',
      'html', 'htm', 'xml', 'svg', 'css', 'js', 'mjs', 'ts', 'dart',
      'py', 'sh', 'bash', 'bat', 'log', 'ini', 'cfg', 'conf',
      'c', 'h', 'cpp', 'cc', 'cxx', 'hpp', 'java', 'go', 'rs',
    };
    return textExts.contains(ext);
  }

  static bool _isImageFile(String name) {
    final ext = name.contains('.')
        ? name.substring(name.lastIndexOf('.') + 1).toLowerCase()
        : '';
    const imageExts = {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'bmp',
      'ico',
    };
    return imageExts.contains(ext);
  }

  static bool _isPdfFile(String name) {
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
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ImagePreviewScreen(
            client: widget.client,
            alias: widget.alias,
            remotePath: entry.path,
            fileName: entry.name,
          ),
        ),
      );
      return;
    }

    if (_isPdfFile(entry.name)) {
      widget.onOpenFile?.call('pdf', entry);
      if (widget.onOpenFile != null) return;
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
    _downloadFile(entry.path, entry.name);
  }

  Widget _buildBottomBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
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
            IconButton(
              icon: const Icon(Icons.cut),
              tooltip: 'Cut',
              onPressed: () {
                _state.cutSelected(widget.alias);
                _state.clearSelection();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Cut to clipboard')),
                );
              },
            ),
            if (_state.clipboard != null)
              IconButton(
                icon: const Icon(Icons.paste),
                tooltip: 'Paste',
                onPressed: _paste,
              ),
            if (_canDelete)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                tooltip: 'Delete selected',
                onPressed: _deleteSelected,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _paste() async {
    final clip = _state.clipboard;
    if (clip == null) return;
    final destination = _state.currentPath;

    if (clip.operation == 'copy') {
      await widget.client
          .batchCopy(widget.alias, clip.items, destination);
    } else {
      await widget.client
          .batchMove(widget.alias, clip.items, destination);
    }
    if (!mounted) return;
    if (clip.operation == 'cut') _state.clearClipboard();
    _state.clearSelection();
    await _load();
  }

  Future<void> _deleteSelected() async {
    final count = _state.selectedPaths.length;
    final confirmed = await showConfirmDeleteDialog(
      context,
      itemCount: count,
    );
    if (!confirmed) return;

    await widget.client
        .batchDelete(widget.alias, _state.selectedPaths.toList());
    if (!mounted) return;
    _state.clearSelection();
    await _load();
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

  void _handleDragCompleted() {
  }

  bool _isInvalidMove(String source, String destination) {
    if (source == destination) return true;
    return destination.startsWith('$source/');
  }

  Future<void> _moveDraggedPaths(
      List<String> paths, String destination) async {
    if (!_canWrite) return;
    if (paths.isEmpty) return;

    final unique = paths.toSet().toList(growable: false);
    if (unique.any((src) => _isInvalidMove(src, destination))) {
      _showError('Cannot move an item into itself or its subfolder.');
      return;
    }

    final result =
        await widget.client.batchMove(widget.alias, unique, destination);
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
