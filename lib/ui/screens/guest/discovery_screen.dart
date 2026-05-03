import 'package:flutter/material.dart';
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

  // Manual connect fields
  final _ipController = TextEditingController();
  final _portController =
      TextEditingController(text: '${AppConstants.defaultPort}');
  final _secretController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _secretController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _hosts = [];
    });
    final found = await _scanner.scan();
    if (!mounted) return;
    setState(() {
      _hosts = found;
      _scanning = false;
    });
  }

  void _connectManual() {
    final ip = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim());
    final secret = _secretController.text.trim();
    if (ip.isEmpty || port == null || secret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('IP, port, and pairing code are required')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExplorerScreen(
          hostAddress: ip,
          port: port,
          pairingSecret: secret,
        ),
      ),
    );
  }

  void _connectDiscovered(DiscoveredHost host) {
    showDialog<String>(
      context: context,
      builder: (_) => _PairingDialog(hostName: host.name),
    ).then((secret) {
      if (secret == null || secret.isEmpty) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ExplorerScreen(
            hostAddress: host.address,
            port: host.port,
            pairingSecret: secret,
          ),
        ),
      );
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
          Text('Discovered on LAN',
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          if (_scanning)
            const Center(child: CircularProgressIndicator())
          else if (_hosts.isEmpty)
            const Text('No hosts found. Try manual connect below.',
                style: TextStyle(color: Colors.grey))
          else
            ..._hosts.map(
              (h) => ListTile(
                leading: const Icon(Icons.computer),
                title: Text(h.name),
                subtitle: Text('${h.address}:${h.port}'),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _connectDiscovered(h),
              ),
            ),

          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 16),

          // Manual connect
          Text('Manual Connect',
              style: Theme.of(context).textTheme.titleSmall),
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
          TextField(
            controller: _secretController,
            decoration: const InputDecoration(
              labelText: 'Pairing code',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.number,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _connectManual,
            child: const Text('Connect'),
          ),
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
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.pop(context, _ctrl.text),
            child: const Text('Connect')),
      ],
    );
  }
}
