import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants.dart';
import '../../../core/host_identity.dart';
import '../../../core/session_store.dart';
import '../../../models/role.dart';
import '../../../models/shared_root.dart';
import '../../../server/server.dart';
import '../../../server/activity/activity_log.dart';

class SessionScreen extends StatefulWidget {
  final OpenFoldrServer server;

  const SessionScreen({super.key, required this.server});

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final List<ActivityEvent> _events = [];
  late String _secret;
  late int _secondsLeft;
  Timer? _expiryTimer;

  InlineSpan get _roleTooltipMessage => TextSpan(
        style: const TextStyle(color: Colors.white, height: 1.5),
        children: const [
          TextSpan(
            text: 'Role Permissions\n',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          TextSpan(
            text: 'Role      Read   Write   Delete   Admin\n',
            style: TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: 'Viewer    Yes    No      No       No\n',
            style: TextStyle(fontFamily: 'monospace'),
          ),
          TextSpan(
            text: 'Editor    Yes    Yes     No       No\n',
            style: TextStyle(fontFamily: 'monospace'),
          ),
          TextSpan(
            text: 'Owner     Yes    Yes     Yes      Yes',
            style: TextStyle(fontFamily: 'monospace'),
          ),
        ],
      );

  Widget _buildRoleTooltip(Widget child) {
    return Tooltip(
      richMessage: _roleTooltipMessage,
      waitDuration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 12,
      ),
      margin: const EdgeInsets.all(12),
      verticalOffset: 16,
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 16,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  void initState() {
    super.initState();
    _renewPairingSecret();
    widget.server.log.stream.listen((e) {
      if (mounted) setState(() => _events.insert(0, e));
    });
  }

  void _renewPairingSecret() {
    _expiryTimer?.cancel();
    setState(() {
      _secret = widget.server.pairing.generateSecret();
      _secondsLeft = AppConstants.pairingSecretExpirySeconds;
    });

    _expiryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_secondsLeft <= 1) {
        _renewPairingSecret();
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  void _syncPairedDeviceRoles() {
    final role = widget.server.roots.highestMinimumRole;
    widget.server.tokens.syncAllRoles(role);
    debugPrint('[SessionScreen] synced paired device roles to ${role.name}');
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    widget.server.stop();
    super.dispose();
  }

  Future<void> _stopSession() async {
    await widget.server.stop();
    if (!mounted) return;
    Navigator.pop(context);
  }

  Future<void> _addSharedFolder() async {
    final pickedPath = await FilePicker.getDirectoryPath();
    if (pickedPath == null) return;

    final alias = _deriveAlias(pickedPath);
    try {
      widget.server.roots.register(
        SharedRoot(
          alias: alias,
          localPath: pickedPath,
          minimumRole: Role.viewer,
        ),
      );
      _syncPairedDeviceRoles();
      await SessionStore.saveRoots(widget.server.roots.all);
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to add folder: $e')));
    }
  }

  void _removeSharedFolder(String alias) {
    widget.server.roots.unregister(alias);
    _syncPairedDeviceRoles();
    SessionStore.saveRoots(widget.server.roots.all);
    setState(() {});
  }

  void _changeMinimumRole(SharedRoot root, Role role) {
    widget.server.roots.unregister(root.alias);
    widget.server.roots.register(
      SharedRoot(
        alias: root.alias,
        localPath: root.localPath,
        minimumRole: role,
      ),
    );
    _syncPairedDeviceRoles();
    SessionStore.saveRoots(widget.server.roots.all);
    setState(() {});
  }

  String _deriveAlias(String path) {
    final base = path.split(Platform.pathSeparator).last;
    var candidate = base
        .replaceAll(RegExp(r'[^a-z0-9_-]', caseSensitive: false), '-')
        .toLowerCase();
    if (candidate.isEmpty) candidate = 'share';

    final existing = widget.server.roots.all.map((e) => e.alias).toSet();
    var suffix = 0;
    var unique = candidate;
    while (existing.contains(unique)) {
      suffix++;
      unique = '$candidate$suffix';
    }
    return unique;
  }

  @override
  Widget build(BuildContext context) {
    final devices = widget.server.tokens.devices;
    final hostName = HostIdentity.name;
    final sharedRoots = widget.server.roots.all;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Session'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.stop_circle),
            tooltip: 'Stop Session',
            onPressed: _stopSession,
          ),
        ],
      ),
      body: Column(
        children: [
          // Security status bar
          Container(
            color: Colors.green.shade50,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.lock, color: Colors.green),
                const SizedBox(width: 8),
                const Text('Encrypted · '),
                Text('Port ${widget.server.port}'),
                const Spacer(),
                Text('${devices.length} device(s) connected'),
              ],
            ),
          ),

          // Pairing code
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'Host Name',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hostName,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Pairing Code',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _secret,
                      style: const TextStyle(
                        fontSize: 40,
                        letterSpacing: 8,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Expires in ${_secondsLeft}s',
                      style: const TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Copy code'),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: _secret));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Code copied')),
                        );
                      },
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Generate new code'),
                      onPressed: _renewPairingSecret,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Shared roots
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Shared folders',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                TextButton.icon(
                  onPressed: _addSharedFolder,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Folder'),
                ),
              ],
            ),
          ),

          if (sharedRoots.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No shared folders yet. Add one to start sharing files.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ...sharedRoots.map(
              (r) => ListTile(
                leading: const Icon(Icons.folder_shared),
                title: Text(r.alias),
                subtitle: Text(r.localPath),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildRoleTooltip(
                      DropdownButton<Role>(
                        value: r.minimumRole,
                        items: Role.values
                            .map(
                              (role) => DropdownMenuItem(
                                value: role,
                                child: Text(role.displayName),
                              ),
                            )
                            .toList(),
                        onChanged: (role) {
                          if (role == null) return;
                          _changeMinimumRole(r, role);
                        },
                      ),
                    ),
                    _buildRoleTooltip(
                      const Padding(
                        padding: EdgeInsets.only(left: 4),
                        child: Icon(
                          Icons.info_outline,
                          size: 18,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Remove shared folder',
                      onPressed: () => _removeSharedFolder(r.alias),
                    ),
                  ],
                ),
              ),
            ),

          const Divider(),

          // Activity log
          Expanded(
            child: _events.isEmpty
                ? const Center(child: Text('No activity yet'))
                : ListView.builder(
                    itemCount: _events.length,
                    itemBuilder: (_, i) {
                      final e = _events[i];
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.history, size: 18),
                        title: Text(
                          '${e.deviceName}: ${e.operation} ${e.path}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(e.timestamp.toLocal().toString()),
                        trailing: Text(
                          e.result,
                          style: TextStyle(
                            color: e.result == 'ok' ? Colors.green : Colors.red,
                            fontSize: 12,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
