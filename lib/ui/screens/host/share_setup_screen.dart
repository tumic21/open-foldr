import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../models/shared_root.dart';
import '../../../models/role.dart';
import '../../../server/server.dart';
import 'session_screen.dart';

class ShareSetupScreen extends StatefulWidget {
  const ShareSetupScreen({super.key});

  @override
  State<ShareSetupScreen> createState() => _ShareSetupScreenState();
}

class _ShareSetupScreenState extends State<ShareSetupScreen> {
  final List<_RootEntry> _entries = [];
  bool _starting = false;

  Future<void> _addFolder() async {
    final result = await FilePicker.platform.getDirectoryPath();
    if (result == null) return;
    final alias = _deriveAlias(result);
    setState(() {
      _entries.add(_RootEntry(path: result, alias: alias));
    });
  }

  String _deriveAlias(String path) {
    final base = path.split(Platform.pathSeparator).last;
    var candidate = base
        .replaceAll(RegExp(r'[^a-z0-9_-]', caseSensitive: false), '-')
        .toLowerCase();
    final existing = _entries.map((e) => e.alias).toSet();
    var suffix = 0;
    var unique = candidate;
    while (existing.contains(unique)) {
      suffix++;
      unique = '$candidate$suffix';
    }
    return unique;
  }

  Future<void> _startSession() async {
    setState(() => _starting = true);

    final server = OpenFoldrServer();
    for (final entry in _entries) {
      server.roots.register(
        SharedRoot(
          alias: entry.alias,
          localPath: entry.path,
          minimumRole: entry.role,
        ),
      );
    }

    try {
      await server.start();
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => SessionScreen(server: server)),
      );
    } catch (e) {
      setState(() => _starting = false);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to start server: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share a Folder')),
      body: Column(
        children: [
          Expanded(
            child: _entries.isEmpty
                ? const Center(child: Text('No folders added yet'))
                : ListView.builder(
                    itemCount: _entries.length,
                    itemBuilder: (_, i) {
                      final e = _entries[i];
                      return ListTile(
                        leading: const Icon(Icons.folder),
                        title: Text(e.alias),
                        subtitle: Text(e.path),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            DropdownButton<Role>(
                              value: e.role,
                              items: Role.values
                                  .map(
                                    (r) => DropdownMenuItem(
                                      value: r,
                                      child: Text(r.displayName),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (r) {
                                if (r == null) return;
                                setState(
                                  () => _entries[i] = _RootEntry(
                                    path: e.path,
                                    alias: e.alias,
                                    role: r,
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () =>
                                  setState(() => _entries.removeAt(i)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add Folder'),
                  onPressed: _addFolder,
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: _starting ? null : _startSession,
                  child: _starting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Start Session'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RootEntry {
  final String path;
  final String alias;
  final Role role;

  const _RootEntry({
    required this.path,
    required this.alias,
    this.role = Role.viewer,
  });
}
