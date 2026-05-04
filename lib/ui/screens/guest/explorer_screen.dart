import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
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
  String? _sessionToken;
  String? _error;
  List<Map<String, dynamic>> _roots = [];
  bool _loading = false;
  bool _requiresNewCode = false;
  String _role = 'viewer';

  String get _base => 'http://${widget.hostAddress}:${widget.port}/v1';

  @override
  void initState() {
    super.initState();
    _pair();
  }

  Future<void> _pair() async {
    setState(() {
      _loading = true;
      _error = null;
      _requiresNewCode = false;
    });
    try {
      // Step 1: request pairing
      final reqRes = await http.post(
        Uri.parse('$_base/auth/pair/request'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'deviceName': 'Guest',
          'devicePublicKey': '',
          'pairingSecret': widget.pairingSecret,
        }),
      );
      if (reqRes.statusCode != 200) {
        final body = jsonDecode(reqRes.body) as Map<String, dynamic>;
        final err = body['error'] as Map<String, dynamic>?;
        final code = err?['code'] as String?;
        final message = err?['message'] as String? ?? 'Pairing request failed';

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
      final requestId =
          (jsonDecode(reqRes.body) as Map<String, dynamic>)['pairRequestId']
              as String;

      final completeRes = await http.post(
        Uri.parse('$_base/auth/pair/complete'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'pairRequestId': requestId}),
      );
      if (completeRes.statusCode != 200) {
        final body = jsonDecode(completeRes.body) as Map<String, dynamic>;
        final err = body['error'] as Map<String, dynamic>?;
        throw Exception(err?['message'] ?? 'Pairing complete failed');
      }

      final token =
          (jsonDecode(completeRes.body) as Map<String, dynamic>)['sessionToken']
              as String;
      final role =
          (jsonDecode(completeRes.body) as Map<String, dynamic>)['role']
              as String? ?? 'viewer';

      setState(() {
        _sessionToken = token;
        _role = role;
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
    final res = await http.get(
      Uri.parse('$_base/roots'),
      headers: {'authorization': 'Bearer $_sessionToken'},
    );
    if (res.statusCode == 200) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _roots = List<Map<String, dynamic>>.from(body['roots'] as List);
        _loading = false;
      });
    } else {
      setState(() {
        _error = 'Failed to load roots';
        _loading = false;
      });
    }
  }

  void _openRoot(String alias) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _BrowseScreen(
          base: _base,
          sessionToken: _sessionToken!,
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
  final String base;
  final String sessionToken;
  final String alias;
  final String path;
  final String role;

  const _BrowseScreen({
    required this.base,
    required this.sessionToken,
    required this.alias,
    required this.path,
    required this.role,
  });

  @override
  State<_BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<_BrowseScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;

  bool get _canWrite => widget.role == 'editor' || widget.role == 'owner';
  bool get _canDelete => widget.role == 'owner';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final uri = Uri.parse(
        '${widget.base}/roots/${widget.alias}/entries',
      ).replace(queryParameters: {'path': widget.path});

      final res = await http.get(
        uri,
        headers: {'authorization': 'Bearer ${widget.sessionToken}'},
      );

      if (res.statusCode != 200) {
        throw Exception('Server error ${res.statusCode}');
      }
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      setState(() {
        _entries = List<Map<String, dynamic>>.from(body['entries'] as List);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
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

    final remotePath = '${widget.path == '/' ? '' : widget.path}/${picked.name}';

    final uri = Uri.parse(
      '${widget.base}/roots/${widget.alias}/file',
    ).replace(queryParameters: {'path': remotePath});

    final res = await http.put(
      uri,
      headers: {
        'authorization': 'Bearer ${widget.sessionToken}',
        'content-type': 'application/octet-stream',
      },
      body: bytes,
    );

    if (!mounted) return;

    if (res.statusCode == 200) {
      await _load();
    } else {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final err = body['error'] as Map<String, dynamic>?;
      _showError(err?['message'] as String? ?? 'Upload failed');
    }
  }

  // ─── Upload a new version of an existing file ────────────────────────────

  Future<void> _uploadNewVersion(String remotePath) async {
    // Fetch current version token first.
    final metaUri = Uri.parse(
      '${widget.base}/roots/${widget.alias}/metadata',
    ).replace(queryParameters: {'path': remotePath});

    final metaRes = await http.get(
      metaUri,
      headers: {'authorization': 'Bearer ${widget.sessionToken}'},
    );
    if (!mounted) return;
    if (metaRes.statusCode != 200) {
      _showError('Could not fetch file metadata');
      return;
    }
    final metaBody = jsonDecode(metaRes.body) as Map<String, dynamic>;
    final versionToken = metaBody['versionToken'] as String;

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
    final uri = Uri.parse(
      '${widget.base}/roots/${widget.alias}/file',
    ).replace(queryParameters: {'path': remotePath});

    final res = await http.put(
      uri,
      headers: {
        'authorization': 'Bearer ${widget.sessionToken}',
        'content-type': 'application/octet-stream',
        'if-match': ifMatch,
      },
      body: bytes,
    );

    if (!mounted) return;

    if (res.statusCode == 200) {
      await _load();
      return;
    }

    if (res.statusCode == 409) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final latestToken = body['versionToken'] as String;
      _showConflictDialog(remotePath, bytes, latestToken);
      return;
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final err = body['error'] as Map<String, dynamic>?;
    _showError(err?['message'] as String? ?? 'Upload failed');
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

    final uri = Uri.parse(
      '${widget.base}/roots/${widget.alias}/file',
    ).replace(queryParameters: {'path': remotePath});

    final res = await http.delete(
      uri,
      headers: {'authorization': 'Bearer ${widget.sessionToken}'},
    );

    if (!mounted) return;

    if (res.statusCode == 200) {
      await _load();
    } else {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final err = body['error'] as Map<String, dynamic>?;
      _showError(err?['message'] as String? ?? 'Delete failed');
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
                      base: widget.base,
                      sessionToken: widget.sessionToken,
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
    final uri = Uri.parse(
      '${widget.base}/roots/${widget.alias}/file',
    ).replace(queryParameters: {'path': remotePath});

    final res = await http.get(
      uri,
      headers: {'authorization': 'Bearer ${widget.sessionToken}'},
    );

    if (!mounted) return;
    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Downloaded $name (${res.bodyBytes.length} bytes)')),
      );
    } else {
      _showError('Download failed: ${res.statusCode}');
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
      appBar: AppBar(title: Text('${widget.alias}${widget.path}')),
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
                      ? const Center(child: Text('Empty folder'))
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
                                            base: widget.base,
                                            sessionToken: widget.sessionToken,
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
