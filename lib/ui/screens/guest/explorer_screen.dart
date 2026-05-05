import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../client/file_client.dart';
import 'file_preview_screen.dart';

class ExplorerScreen extends StatefulWidget {
  final String hostAddress;
  final int port;
  final String pairingSecret;

  const ExplorerScreen({
    super.key,
    required this.hostAddress,
    required this.port,
    required this.pairingSecret,
  });

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  String? _error;
  List<Map<String, dynamic>> _roots = [];
  bool _loading = false;
  bool _requiresNewCode = false;
  String _role = 'viewer';
  FileClient? _client;

  String get _base => 'http://${widget.hostAddress}:${widget.port}/v1';

  @override
  void initState() {
    super.initState();
    _pair();
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  Future<void> _pair() async {
    setState(() {
      _loading = true;
      _error = null;
      _requiresNewCode = false;
    });
    try {
      final result = await FileClient.pair(
        baseUrl: _base,
        pairingSecret: widget.pairingSecret,
      );

      if (result.isErr) {
        final code = result.errorCode;
        final message = result.errorMessage;
        if (code == 'NO_ACTIVE_SECRET' || code == 'SECRET_EXPIRED') {
          throw _PairingCodeException(
            'Pairing code is expired or already used. Ask host for a new code.',
          );
        }
        if (code == 'INVALID_SECRET') {
          throw _PairingCodeException(
            'Pairing code is invalid. Check code and retry.',
          );
        }
        throw Exception(message);
      }

      final pairData = result.unwrap;
      _client = pairData.client;

      setState(() {
        _role = pairData.role;
      });
      await _loadRoots();
    } on _PairingCodeException catch (e) {
      setState(() {
        _error = e.message;
        _requiresNewCode = true;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadRoots() async {
    final result = await _client!.listRoots();
    if (result.isOk) {
      setState(() {
        _roots = result.unwrap;
        _loading = false;
      });
    } else {
      setState(() {
        _error = result.errorMessage;
        _loading = false;
      });
    }
  }

  void _openRoot(String alias) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _BrowseScreen(
          client: _client!,
          alias: alias,
          path: '/',
          role: _role,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Connect')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                if (_requiresNewCode)
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back and enter new code'),
                  )
                else
                  FilledButton(onPressed: _pair, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.hostAddress),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Row(
              children: const [
                Icon(Icons.lock, size: 16, color: Colors.green),
                SizedBox(width: 4),
                Text('Connected', style: TextStyle(color: Colors.green)),
              ],
            ),
          ),
        ],
      ),
      body: _roots.isEmpty
          ? const Center(child: Text('No shared folders available'))
          : ListView.builder(
              itemCount: _roots.length,
              itemBuilder: (_, i) {
                final root = _roots[i];
                return ListTile(
                  leading: const Icon(Icons.folder_shared),
                  title: Text(root['alias'] as String),
                  subtitle: Text('Role: ${root['minimumRole']}'),
                  trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _openRoot(root['alias'] as String),
                );
              },
            ),
    );
  }
}

class _PairingCodeException implements Exception {
  final String message;

  _PairingCodeException(this.message);
}

class _BrowseScreen extends StatefulWidget {
  final FileClient client;
  final String alias;
  final String path;
  final String role;

  const _BrowseScreen({
    required this.client,
    required this.alias,
    required this.path,
    required this.role,
  });

  @override
  State<_BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<_BrowseScreen> {
  static const _downloadFolderPrefKey = 'guest.downloadFolder';

  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;
  String? _downloadFolder;

  bool get _canWrite => widget.role == 'editor' || widget.role == 'owner';
  bool get _canDelete => widget.role == 'owner';

  @override
  void initState() {
    super.initState();
    _load();
    _loadDownloadFolder();
  }

  String _defaultDownloadFolder() {
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? '';
    if (home.isEmpty) return 'Downloads/OpenFoldr';
    return p.join(home, 'Downloads', 'OpenFoldr');
  }

  Future<void> _loadDownloadFolder() async {
    final prefs = await SharedPreferences.getInstance();
    final configured = prefs.getString(_downloadFolderPrefKey);
    if (!mounted) return;
    setState(() {
      _downloadFolder = configured ?? _defaultDownloadFolder();
    });
  }

  Future<void> _saveDownloadFolder(String folder) async {
    final normalized = folder.trim();
    if (normalized.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_downloadFolderPrefKey, normalized);
    if (!mounted) return;
    setState(() {
      _downloadFolder = normalized;
    });
  }

  Future<void> _showSettingsDialog() async {
    final initialFolder = _downloadFolder ?? _defaultDownloadFolder();
    final controller = TextEditingController(text: initialFolder);

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
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
                    final selected = await FilePicker.platform.getDirectoryPath();
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
        );
      },
    );

    if (shouldSave == true) {
      await _saveDownloadFolder(controller.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download folder set to ${controller.text.trim()}')),
      );
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.client.listEntries(widget.alias, widget.path);
    if (!mounted) return;
    if (result.isOk) {
      setState(() {
        _entries = result.unwrap
            .map((e) => {
                  'name': e.name,
                  'path': e.path,
                  'kind': e.kind,
                  'size': e.size,
                  'modifiedAt': e.modifiedAt.toIso8601String(),
                })
            .toList();
        _loading = false;
      });
    } else {
      setState(() {
        _error = result.errorMessage;
        _loading = false;
      });
    }
  }

  // ─── Upload a new file into the current directory ────────────────────────

  Future<void> _uploadNewFile() async {
    final result = await FilePicker.platform.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;

    final picked = result.files.first;
    final bytes = picked.bytes;
    if (bytes == null) return;

    final remotePath =
        '${widget.path == '/' ? '' : widget.path}/${picked.name}';

    final uploadResult = await widget.client.uploadFile(
      widget.alias,
      remotePath,
      bytes,
    );

    if (!mounted) return;

    if (uploadResult.isOk) {
      await _load();
    } else {
      _showError(uploadResult.errorMessage);
    }
  }

  // ─── Upload a new version of an existing file ────────────────────────────

  Future<void> _uploadNewVersion(String remotePath) async {
    final metaResult =
        await widget.client.getMetadata(widget.alias, remotePath);
    if (!mounted) return;
    if (metaResult.isErr) {
      _showError('Could not fetch file metadata');
      return;
    }
    final versionToken = metaResult.unwrap.versionToken;

    final picked = await FilePicker.platform.pickFiles(withData: true);
    if (picked == null || picked.files.isEmpty) return;
    final bytes = picked.files.first.bytes;
    if (bytes == null) return;

    await _doPut(remotePath, bytes, ifMatch: versionToken);
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
      await _load();
      return;
    }

    if (result.errorCode == 'VERSION_CONFLICT') {
      // Re-fetch the latest token so we can offer retry.
      final metaResult =
          await widget.client.getMetadata(widget.alias, remotePath);
      final latestToken =
          metaResult.isOk ? metaResult.unwrap.versionToken : '*';
      _showConflictDialog(remotePath, bytes, latestToken);
      return;
    }

    _showError(result.errorMessage);
  }

  // ─── Conflict resolution dialog ──────────────────────────────────────────

  void _showConflictDialog(
    String remotePath,
    Uint8List bytes,
    String latestToken,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Version Conflict'),
        content: const Text(
          'This file was modified by another client. '
          'How would you like to proceed?',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
            },
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Save as copy with a timestamp suffix.
              final ext = remotePath.contains('.')
                  ? remotePath.substring(remotePath.lastIndexOf('.'))
                  : '';
              final base = ext.isNotEmpty
                  ? remotePath.substring(0, remotePath.lastIndexOf('.'))
                  : remotePath;
              final copyPath =
                  '${base}_copy_${DateTime.now().millisecondsSinceEpoch}$ext';
              await _doPut(copyPath, bytes, ifMatch: '');
            },
            child: const Text('Save as Copy'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              // Retry with the latest known token.
              await _doPut(remotePath, bytes, ifMatch: latestToken);
            },
            child: const Text('Retry with Latest'),
          ),
          if (_canDelete)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                // Force-overwrite using wildcard.
                await _doPut(remotePath, bytes, ifMatch: '*');
              },
              child: const Text('Force Overwrite'),
            ),
        ],
      ),
    );
  }

  // ─── Delete a single file/directory ─────────────────────────────────────

  Future<void> _deleteEntry(String remotePath, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Delete'),
        content: Text('Delete "$name"? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await widget.client.deleteItem(widget.alias, remotePath);

    if (!mounted) return;

    if (result.isOk) {
      await _load();
    } else {
      _showError(result.errorMessage);
    }
  }

  // ─── File action bottom sheet ────────────────────────────────────────────

  void _showFileActions(Map<String, dynamic> entry) {
    final remotePath = entry['path'] as String;
    final name = entry['name'] as String? ?? remotePath;
    final isDir = entry['kind'] == 'directory';
    final size = entry['size'] as int? ?? 0;

    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
                      remotePath: remotePath,
                      fileName: name,
                      fileSize: size,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Download'),
              onTap: () {
                Navigator.pop(ctx);
                _downloadFile(remotePath, name);
              },
            ),
            if (_canWrite && !isDir)
              ListTile(
                leading: const Icon(Icons.upload_file),
                title: const Text('Upload New Version'),
                onTap: () {
                  Navigator.pop(ctx);
                  _uploadNewVersion(remotePath);
                },
              ),
            if (_canDelete)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _deleteEntry(remotePath, name);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadFile(String remotePath, String name) async {
    final result = await widget.client.downloadFile(widget.alias, remotePath);

    if (!mounted) return;
    if (result.isOk) {
      final downloadFolder = _downloadFolder ?? _defaultDownloadFolder();
      final directory = Directory(downloadFolder);
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }

      final fileName = p.basename(name.isNotEmpty ? name : remotePath);
      final outputPath = p.join(downloadFolder, fileName);
      await File(outputPath).writeAsBytes(result.unwrap, flush: true);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to $outputPath')),
      );
    } else {
      _showError('Download failed: ${result.errorMessage}');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.alias}${widget.path}'),
        actions: [
          IconButton(
            onPressed: _showSettingsDialog,
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
          ),
        ],
      ),
      floatingActionButton: _canWrite
          ? FloatingActionButton(
              onPressed: _uploadNewFile,
              tooltip: 'Upload file',
              child: const Icon(Icons.upload_file),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _entries.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 120),
                            Center(child: Text('Empty folder')),
                          ],
                        )
                      : ListView.builder(
                          itemCount: _entries.length,
                          itemBuilder: (_, i) {
                            final entry = _entries[i];
                            final isDir = entry['kind'] == 'directory';
                            return ListTile(
                              leading: Icon(
                                isDir
                                    ? Icons.folder
                                    : Icons.insert_drive_file,
                              ),
                              title: Text(entry['name'] as String? ?? ''),
                              subtitle: isDir
                                  ? null
                                  : Text(
                                      _formatSize(entry['size'] as int? ?? 0),
                                    ),
                              trailing: const Icon(
                                Icons.more_vert,
                                size: 18,
                              ),
                              onTap: isDir
                                  ? () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => _BrowseScreen(
                                            client: widget.client,
                                            alias: widget.alias,
                                            path: entry['path'] as String,
                                            role: widget.role,
                                          ),
                                        ),
                                      )
                                  : () => _showFileActions(entry),
                              onLongPress: () => _showFileActions(entry),
                            );
                          },
                        ),
                ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
