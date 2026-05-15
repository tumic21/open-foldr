part of 'session_screen.dart';

extension _SessionScreenUI on _SessionScreenState {
  /// Build the security status bar at the top
  Widget _buildSecurityStatusBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final barColor = isDark
        ? const Color(0xFF1B5E20)
        : const Color(0xFFE8F5E9);
    final contentColor = isDark
        ? const Color(0xFFE8F5E9)
        : const Color(0xFF1B5E20);
    final devices = widget.server.tokens.connectedDevices();
    return Container(
      color: barColor,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(Icons.lock, color: contentColor),
          const SizedBox(width: 8),
          Text(
            'Encrypted · ',
            style: TextStyle(color: contentColor),
          ),
          Text(
            'Port ${widget.server.port}',
            style: TextStyle(color: contentColor),
          ),
          const Spacer(),
          Text(
            '${devices.length} device(s) connected',
            style: TextStyle(color: contentColor),
          ),
        ],
      ),
    );
  }

  /// Build the pairing code card
  Widget _buildPairingCard() {
    final theme = Theme.of(context);
    final hostName = HostIdentity.name;
    return Padding(
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Host IP: $_hostIp',
                    style: TextStyle(
                      fontSize: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_hostIpAddresses.length > 1) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      tooltip: _showAllHostIps
                          ? 'Hide all IP addresses'
                          : 'Show all IP addresses',
                      icon: Icon(
                        _showAllHostIps ? Icons.remove : Icons.add,
                        size: 18,
                      ),
                      onPressed: () {
                        setState(() {
                          _showAllHostIps = !_showAllHostIps;
                        });
                      },
                    ),
                  ],
                ],
              ),
              if (_showAllHostIps && _hostIpAddresses.length > 1)
                _buildHostIpsExpanded(),
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
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
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
    );
  }

  /// Build the expanded list of host IP addresses
  Widget _buildHostIpsExpanded() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outlineVariant,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'All IP addresses',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _hostIpAddresses.map(
                (ip) => GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: ip));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Copied: $ip'),
                        duration: const Duration(seconds: 2),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: colorScheme.outlineVariant,
                        width: 1,
                      ),
                    ),
                    child: Text(
                      ip,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ).toList(),
            ),
            const SizedBox(height: 6),
            Text(
              'Click any address to copy',
              style: TextStyle(
                fontSize: 11,
                color: colorScheme.primary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build the shared folders section
  Widget _buildSharedFoldersSection() {
    final sharedRoots = widget.server.roots.all;
    return Column(
      children: [
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
            (r) => LayoutBuilder(
              builder: (context, constraints) {
                // Use custom layout on narrow screens (< 500px)
                final isNarrow = constraints.maxWidth < 500;
                
                if (isNarrow) {
                  return Card(
                    margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Image.asset('assets/icons/icon.png',
                                  width: 32, height: 32),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      r.alias,
                                      style: Theme.of(context).textTheme.titleSmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            r.localPath,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: _buildRoleTooltip(
                                  DropdownMenu<Role>(
                                    initialSelection: r.minimumRole,
                                    width: double.infinity,
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
                              ),
                              _buildRoleTooltip(
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 4),
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
                        ],
                      ),
                    ),
                  );
                } else {
                  return ListTile(
                    leading: Image.asset('assets/icons/icon.png',
                        width: 32, height: 32),
                    title: Text(r.alias),
                    subtitle: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.localPath,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
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
                  );
                }
              },
            ),
          ),
      ],
    );
  }

  /// Build the trusted clients section
  Widget _buildTrustedClientsSection() {
    return Column(
      children: [
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
                'ID: ${c.deviceId} · Paired ${_formatDate(c.pairedAt)}',
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
      ],
    );
  }

  /// Build the activity log section
  Widget _buildActivityLogSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'Activity Log',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        if (_events.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: Text('No activity yet')),
          )
        else
          ListView.builder(
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
    );
  }

  /// Helper: Build a tooltip-wrapped widget for role information
  Widget _buildRoleTooltip(Widget child) {
    return Tooltip(
      message:
          'Sets minimum permission level required for clients to access this folder',
      child: child,
    );
  }
}
