import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../../../core/constants.dart';
import '../../../core/host_identity.dart';
import '../../../core/session_store.dart';
import '../../../core/trusted_client_store.dart';
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
  Timer? _trustedRefreshTimer;
  List<TrustedClient> _trustedClients = [];
  String _hostIp = 'Detecting...';

  InlineSpan get _roleTooltipMessage => TextSpan(
    style: const TextStyle(color: Colors.white, height: 1.5),
    children: const [
      TextSpan(
        text: 'Role Permissions\n',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      TextSpan(
        text: 'Role      Read   Write   Delete   Admin\n',
        style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
    WakelockPlus.enable();
    _renewPairingSecret();
    _loadHostIp();
    _loadTrustedClients();
    _trustedRefreshTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _loadTrustedClients(),
    );
    widget.server.log.stream.listen((e) {
      if (mounted) setState(() => _events.insert(0, e));
    });
  }

  Future<void> _loadHostIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.any,
      );

      final allAddresses = interfaces
          .expand((i) => i.addresses)
          .where((a) => !a.isLoopback)
          .toList();

      final ipv4 = allAddresses.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => allAddresses.isNotEmpty
            ? allAddresses.first
            : InternetAddress.anyIPv4,
      );

      if (!mounted) return;
      setState(() => _hostIp = ipv4.address);
    } catch (_) {
      if (!mounted) return;
      setState(() => _hostIp = 'Unavailable');
    }
  }

  Future<void> _loadTrustedClients() async {
    final clients = await TrustedClientStore.load();
    if (mounted) setState(() => _trustedClients = clients);
  }

  Future<void> _removeTrustedClient(String deviceId) async {
    await TrustedClientStore.remove(deviceId);
    widget.server.tokens.revokeDevice(deviceId);
    if (mounted) {
      setState(
        () => _trustedClients.removeWhere((c) => c.deviceId == deviceId),
      );
    }
  }

  void _confirmRemoveTrustedClient(TrustedClient client) {
    showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove client?'),
        content: Text(
          '"${client.deviceName}" will need to pair again with a new code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) _removeTrustedClient(client.deviceId);
    });
  }

  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
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
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _expiryTimer?.cancel();
    _trustedRefreshTimer?.cancel();
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
    final devices = widget.server.tokens.connectedDevices();
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
      body: SingleChildScrollView(
        child: Column(
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
                    const SizedBox(height: 8),
                    Text(
                      'Host IP: $_hostIp',
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                        fontWeight: FontWeight.w600,
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
                leading: Image.asset('assets/icons/icon.png', width: 32, height: 32),
                title: Text(r.alias),
                subtitle: Text(r.localPath),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildRoleTooltip(
                      DropdownMenu<Role>(
                        initialSelection: r.minimumRole,
                        width: 130,
                        inputDecorationTheme: InputDecorationTheme(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(20),
                            borderSide: BorderSide.none,
                          ),
                          filled: true,
                        ),
                        textStyle: Theme.of(context).textTheme.bodyMedium,
                        dropdownMenuEntries: Role.values
                            .map(
                              (role) => DropdownMenuEntry(
                                value: role,
                                label: role.displayName,
                              ),
                            )
                            .toList(),
                        onSelected: (role) {
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

          // Trusted (remembered) clients
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Remembered clients',
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          if (_trustedClients.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'No remembered clients yet.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ..._trustedClients.map(
              (c) => ListTile(
                dense: true,
                leading: const Icon(Icons.devices),
                title: Text(
                  c.deviceName == 'Guest'
                      ? 'Client ${c.deviceId.substring(0, 8)}'
                      : c.deviceName,
                ),
                subtitle: Text(
                  'ID: ${c.deviceId} · Role: ${c.role.displayName} · Paired ${_formatDate(c.pairedAt)}',
                ),
                trailing: IconButton(
                  icon: const Icon(
                    Icons.remove_circle_outline,
                    color: Colors.red,
                  ),
                  tooltip: 'Remove & revoke',
                  onPressed: () => _confirmRemoveTrustedClient(c),
                ),
              ),
            ),

          const Divider(),

          // Activity log
          _events.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: Text('No activity yet')),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
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
        ],
        ),
      ),
    );
  }
}
