import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/constants.dart';
import '../../../models/role.dart';
import '../../../server/handlers/handlers.dart';
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

  void _approveRequest(String requestId, Role role) {
    approvePairRequest(requestId, role: role);
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Approved device as ${role.displayName}')),
    );
  }

  void _denyRequest(String requestId) {
    denyPairRequest(requestId);
    setState(() {});
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Pairing request denied')));
  }

  @override
  Widget build(BuildContext context) {
    final devices = widget.server.tokens.devices;
    final pending = pendingPairRequests;

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
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Shared folders',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
          ),

          if (pending.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pending Device Approvals (${pending.length})',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: 8),
                      ...pending.map(
                        (req) => ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.devices),
                          title: Text(req.deviceName),
                          subtitle: Text(req.ip),
                          trailing: Wrap(
                            spacing: 6,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    _approveRequest(req.id, Role.viewer),
                                child: const Text('Approve'),
                              ),
                              TextButton(
                                onPressed: () => _denyRequest(req.id),
                                child: const Text('Deny'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          ...widget.server.roots.all.map(
            (r) => ListTile(
              leading: const Icon(Icons.folder_shared),
              title: Text(r.alias),
              subtitle: Text(r.localPath),
              trailing: Text(
                r.minimumRole.displayName,
                style: const TextStyle(color: Colors.grey),
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
