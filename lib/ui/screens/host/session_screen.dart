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

part 'session_screen_logic.dart';
part 'session_screen_ui.dart';

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
  List<String> _hostIpAddresses = const [];
  bool _showAllHostIps = false;

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

  @override
  void dispose() {
    WakelockPlus.disable();
    _expiryTimer?.cancel();
    _trustedRefreshTimer?.cancel();
    widget.server.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
            _buildSecurityStatusBar(),
            _buildPairingCard(),
            _buildSharedFoldersSection(),
            const Divider(),
            _buildTrustedClientsSection(),
            const Divider(),
            _buildActivityLogSection(),
          ],
        ),
      ),
    );
  }
}
