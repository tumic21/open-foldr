import 'dart:async';

import 'package:flutter/material.dart';
import '../../../core/client_credential_store.dart';
import '../../../discovery/mdns_scanner.dart';
import '../../../core/constants.dart';
import 'explorer_screen.dart';

class DiscoveryScreen extends StatefulWidget {
  const DiscoveryScreen({super.key});

  @override
  State<DiscoveryScreen> createState() => _DiscoveryScreenState();
}

class _DiscoveryScreenState extends State<DiscoveryScreen> {
  final _scanner = MdnsScanner();
  List<DiscoveredHost> _hosts = [];
  bool _scanning = false;
  bool _keepScanning = true;

  // Manual connect fields
  final _ipController = TextEditingController();
  final _portController = TextEditingController(
    text: '${AppConstants.defaultPort}',
  );

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _keepScanning = false;
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    _keepScanning = true;
    while (_keepScanning && mounted) {
      setState(() {
        _scanning = true;
        if (_hosts.isEmpty) _hosts = [];
      });
      final found = await _scanner.scan(
        onUpdate: (hosts) {
          if (!mounted) return;
          setState(() => _hosts = hosts);
        },
      );
      if (!mounted) break;
      setState(() => _hosts = found);
      // Brief pause before next scan cycle so the UI can settle.
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (mounted) setState(() => _scanning = false);
  }

  void _connectManual() {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    if (ip.isEmpty || port == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('IP and port are required')));
      return;
    }
    // For manual connect we don't have the hostId yet, so open pairing dialog.
    showDialog<String>(
      context: context,
      builder: (_) => _PairingDialog(hostName: ip),
    ).then((secret) {
      if (secret == null || secret.isEmpty) return;
      _keepScanning = false;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExplorerScreen(
            hostAddress: ip,
            port: port,
            pairingSecret: secret,
            // hostId unknown for manual connect; will be discovered on connect.
          ),
        ),
      );
    });
  }

  void _connectDiscovered(DiscoveredHost host) {
    // Check if we already have credentials for this host.
    ClientCredentialStore.find(host.hostId).then((cred) {
      if (!mounted) return;
      if (cred != null) {
        // Known host — connect silently (ExplorerScreen will use stored token).
        _keepScanning = false;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExplorerScreen(
              hostAddress: host.address,
              port: host.port,
              pairingSecret: '',
              hostId: host.hostId,
            ),
          ),
        );
        return;
      }
      // Unknown host — ask for pairing code.
      showDialog<String>(
        context: context,
        builder: (_) => _PairingDialog(hostName: host.name),
      ).then((secret) {
        if (secret == null || secret.isEmpty) return;
        _keepScanning = false;
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ExplorerScreen(
              hostAddress: host.address,
              port: host.port,
              pairingSecret: secret,
              hostId: host.hostId,
            ),
          ),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join a Share'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _scanning ? null : _scan,
            tooltip: 'Scan again',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Discovered hosts
          Text(
            'Discovered on LAN',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          if (_hosts.isEmpty && _scanning)
            const Center(child: CircularProgressIndicator())
          else if (_hosts.isEmpty)
            const Text(
              'No hosts found. Try manual connect below.',
              style: TextStyle(color: Colors.grey),
            )
          else
            Column(
              children: [
                if (_scanning)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Scanning... found hosts are shown immediately',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ..._hosts.map(
                  (h) => ListTile(
                    leading: const Icon(Icons.computer),
                    title: Text(h.name),
                    subtitle: Text('${h.address}:${h.port}'),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                    onTap: () => _connectDiscovered(h),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // Manual connect
          Text('Manual Connect', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          TextField(
            controller: _ipController,
            decoration: const InputDecoration(
              labelText: 'Host IP or hostname',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _portController,
            decoration: const InputDecoration(
              labelText: 'Port',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _connectManual, child: const Text('Connect')),
        ],
      ),
    );
  }
}

class _PairingDialog extends StatefulWidget {
  final String hostName;
  const _PairingDialog({required this.hostName});

  @override
  State<_PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<_PairingDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Connect to ${widget.hostName}'),
      content: TextField(
        controller: _ctrl,
        decoration: const InputDecoration(labelText: 'Pairing code'),
        keyboardType: TextInputType.number,
        autofocus: true,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text),
          child: const Text('Connect'),
        ),
      ],
    );
  }
}
