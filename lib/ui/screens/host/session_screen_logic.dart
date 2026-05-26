part of 'session_screen.dart';

extension _SessionScreenLogic on _SessionScreenState {
  /// Load the host's IP address from network interfaces
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

      final uniqueAddresses = <String>{
        for (final address in allAddresses) address.address,
      }.toList();

      final ipv4 = allAddresses.firstWhere(
        (a) => a.type == InternetAddressType.IPv4,
        orElse: () => allAddresses.isNotEmpty
            ? allAddresses.first
            : InternetAddress.anyIPv4,
      );

      if (!mounted) return;
      setState(() {
        _hostIp = ipv4.address;
        _hostIpAddresses = uniqueAddresses;
        if (_hostIpAddresses.length <= 1) {
          _showAllHostIps = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _hostIp = 'Unavailable';
        _hostIpAddresses = const [];
        _showAllHostIps = false;
      });
    }
  }

  /// Load trusted (remembered) client devices
  Future<void> _loadTrustedClients() async {
    final clients = await TrustedClientStore.load();
    if (mounted) setState(() => _trustedClients = clients);
  }

  /// Remove a trusted client device and revoke its token
  Future<void> _removeTrustedClient(String deviceId) async {
    await TrustedClientStore.remove(deviceId);
    widget.server.tokens.revokeDevice(deviceId);
    if (mounted) {
      setState(
        () => _trustedClients.removeWhere((c) => c.deviceId == deviceId),
      );
    }
  }

  /// Show confirmation dialog before removing a trusted client
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

  /// Format a DateTime as YYYY-MM-DD string
  String _formatDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  /// Generate a new pairing secret and reset expiry timer
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

  /// Sync all paired devices' roles to match the highest minimum role
  void _syncPairedDeviceRoles() {
    final role = widget.server.roots.highestMinimumRole;
    widget.server.tokens.syncAllRoles(role);
  }

  /// Stop the session and return to previous screen
  Future<void> _stopSession() async {
    await widget.server.stop();
    if (!mounted) return;
    Navigator.pop(context);
  }

  /// Add a new shared folder.
  Future<void> _addSharedFolder() async {
    final pickedPath = await selectSharedFolderPath(context);
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

  /// Remove a shared folder by alias
  void _removeSharedFolder(String alias) {
    widget.server.roots.unregister(alias);
    _syncPairedDeviceRoles();
    SessionStore.saveRoots(widget.server.roots.all);
    setState(() {});
  }

  /// Change the minimum role required for a shared folder
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

  /// Derive a unique alias from a folder path
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
}
