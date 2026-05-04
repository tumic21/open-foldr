import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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

      setState(() => _sessionToken = token);
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
        title: Text('${widget.hostAddress}'),
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

  const _BrowseScreen({
    required this.base,
    required this.sessionToken,
    required this.alias,
    required this.path,
  });

  @override
  State<_BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<_BrowseScreen> {
  List<Map<String, dynamic>> _entries = [];
  bool _loading = true;
  String? _error;

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

      if (res.statusCode != 200)
        throw Exception('Server error ${res.statusCode}');
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.alias}${widget.path}')),
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
                            isDir ? Icons.folder : Icons.insert_drive_file,
                          ),
                          title: Text(entry['name'] as String? ?? ''),
                          subtitle: isDir
                              ? null
                              : Text(_formatSize(entry['size'] as int? ?? 0)),
                          onTap: isDir
                              ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => _BrowseScreen(
                                      base: widget.base,
                                      sessionToken: widget.sessionToken,
                                      alias: widget.alias,
                                      path: entry['path'] as String,
                                    ),
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
            ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
