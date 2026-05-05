import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../client/file_client.dart';
import '../../widgets/file_manager/breadcrumb_bar.dart';
import '../../widgets/file_manager/dialogs/confirm_delete_dialog.dart';
import '../../widgets/file_manager/dialogs/conflict_dialog.dart';
import '../../widgets/file_manager/dialogs/create_folder_dialog.dart';
import '../../widgets/file_manager/dialogs/properties_dialog.dart';
import '../../widgets/file_manager/dialogs/rename_dialog.dart';
import '../../widgets/file_manager/file_grid_tile.dart';
import '../../widgets/file_manager/file_list_tile.dart';
import '../../widgets/file_manager/sort_menu.dart';
import '../../widgets/file_manager/view_mode_toggle.dart';
import 'file_preview_screen.dart';
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
    notifyListeners();
  }

  bool popPath() {
    if (_pathStack.length <= 1) return false;
    _pathStack.removeLast();
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

// ─── FileManagerScreen ───────────────────────────────────────────────────────

class FileManagerScreen extends StatefulWidget {
  final FileClient client;
  final String alias;
  final String role;
  final String initialPath;

  const FileManagerScreen({
    super.key,
    required this.client,
    required this.alias,
    required this.role,
    this.initialPath = '/',
  });

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  static const _downloadFolderPrefKey = 'guest.downloadFolder';

  late final FileManagerState _state;
  String? _downloadFolder;

  bool get _canWrite =>
      widget.role == 'editor' || widget.role == 'owner';
  bool get _canDelete => widget.role == 'owner';

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
  }

  // ─── Upload ────────────────────────────────────────────────────────────────

  Future<void> _uploadNewFile() async {
    final picked =
        await FilePicker.platform.pickFiles(withData: true);
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
        await FilePicker.platform.pickFiles(withData: true);
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
                      await FilePicker.platform.getDirectoryPath();
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

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final goBack = await _onWillPop();
        if (goBack && context.mounted) Navigator.pop(context);
        if (!goBack) await _load();
      },
      child: Scaffold(
        appBar: _buildAppBar(),
        body: Column(
          children: [
            BreadcrumbBar(
              alias: widget.alias,
              currentPath: _state.currentPath,
              onNavigateTo: (path) async {
                _state.navigateTo(path);
                _state.clearSelection();
                await _load();
              },
            ),
            Expanded(child: _buildBody()),
          ],
        ),
        floatingActionButton: _canWrite && !_state.multiSelectMode
            ? FloatingActionButton(
                tooltip: 'New',
                onPressed: _showNewItemMenu,
                child: const Icon(Icons.add),
              )
            : null,
        bottomNavigationBar: _state.hasSelection ? _buildBottomBar() : null,
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
        ],
      );
    }

    return AppBar(
      title: Text(widget.alias),
      actions: [
        ViewModeToggle(
          mode: _state.viewMode,
          onChanged: _state.setViewMode,
        ),
        SortMenu(
          sortBy: _state.sortBy,
          sortOrder: _state.sortOrder,
          onChanged: _state.setSortBy,
        ),
        IconButton(
          icon: const Icon(Icons.settings),
          tooltip: 'Settings',
          onPressed: _showSettingsDialog,
        ),
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
    if (_state.entries.isEmpty) {
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: const [
            SizedBox(height: 120),
            Center(child: Text('Empty folder')),
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
          itemCount: _state.entries.length,
          itemBuilder: (_, i) {
            final entry = _state.entries[i];
            return FileGridTile(
              entry: entry,
              selected: _state.selectedPaths.contains(entry.path),
              multiSelectMode: _state.multiSelectMode,
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
        itemCount: _state.entries.length,
        itemBuilder: (_, i) {
          final entry = _state.entries[i];
          return FileListTile(
            entry: entry,
            selected: _state.selectedPaths.contains(entry.path),
            multiSelectMode: _state.multiSelectMode,
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

  void _openFile(FileEntry entry) {
    if (_isTextFile(entry.name)) {
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
    // Non-text: open preview (images, binary, etc.)
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
