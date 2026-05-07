import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../client/file_client.dart';
import '../../../core/client_credential_store.dart';
import 'file_manager_screen.dart';

class ExplorerScreen extends StatefulWidget {
  final String hostAddress;
  final int port;
  final String pairingSecret;

  /// Stable host id from the /v1/health response (used for credential lookup).
  final String? hostId;

  const ExplorerScreen({
    super.key,
    required this.hostAddress,
    required this.port,
    required this.pairingSecret,
    this.hostId,
  });

  @override
  State<ExplorerScreen> createState() => _ExplorerScreenState();
}

class _ExplorerScreenState extends State<ExplorerScreen> {
  String? _error;
  List<Map<String, dynamic>> _roots = [];
  bool _loading = false;
  bool _requiresNewCode = false;
  String _role = 'viewer';
  FileClient? _client;
  String? _knownDeviceId;

  String get _base => 'http://${widget.hostAddress}:${widget.port}/v1';

  Future<({String? id, String? name})> _resolveHostInfo() async {
    if (widget.hostId != null && widget.hostId!.isNotEmpty) {
      return (id: widget.hostId, name: null);
    }
    try {
      final res = await http.get(Uri.parse('$_base/health'));
      if (res.statusCode != 200) return (id: null, name: null);
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final host = body['host'] as Map<String, dynamic>?;
      final id = host?['id'] as String?;
      final name = host?['name'] as String?;
      if (id == null || id.isEmpty) return (id: null, name: name);
      return (id: id, name: name);
    } catch (_) {
      return (id: null, name: null);
    }
  }

  @override
  void initState() {
    super.initState();
    _pair();
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }

  Future<void> _pair() async {
    setState(() {
      _loading = true;
      _error = null;
      _requiresNewCode = false;
    });
    try {
      final hostInfo = await _resolveHostInfo();
      final effectiveHostId = hostInfo.id;
      final effectiveHostName = hostInfo.name ?? widget.hostAddress;

      // ── Try reconnect with stored device token first ──────────────────────
      if (effectiveHostId != null) {
        final cred = await ClientCredentialStore.find(effectiveHostId);
        if (cred != null) {
          _knownDeviceId = cred.deviceId;
          final reconnResult = await FileClient.reconnect(
            baseUrl: _base,
            deviceToken: cred.deviceToken,
            deviceId: cred.deviceId,
          );
          if (reconnResult.isOk) {
            final pairData = reconnResult.unwrap;
            _client = pairData.client;
            setState(() => _role = pairData.role);
            await _loadRoots();
            return;
          }
          // Token revoked or expired — fall through to full pairing.
          await ClientCredentialStore.remove(effectiveHostId);
        }
      }

      // ── Full pairing handshake ────────────────────────────────────────────
      final result = await FileClient.pair(
        baseUrl: _base,
        pairingSecret: widget.pairingSecret,
        deviceId: _knownDeviceId,
      );

      if (result.isErr) {
        final code = result.errorCode;
        final message = result.errorMessage;
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

      final pairData = result.unwrap;
      _client = pairData.client;

      // Persist credentials so we can reconnect silently next time.
      if (effectiveHostId != null &&
          pairData.deviceToken.isNotEmpty &&
          pairData.deviceId.isNotEmpty) {
        unawaited(
          ClientCredentialStore.save(
            hostId: effectiveHostId,
            hostName: effectiveHostName,
            hostAddress: widget.hostAddress,
            port: widget.port,
            deviceToken: pairData.deviceToken,
            deviceId: pairData.deviceId,
          ),
        );
      }

      setState(() => _role = pairData.role);
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
    final roleResult = await _client!.getSessionRole();
    if (roleResult.isOk) {
      _role = roleResult.unwrap;
    }
    final result = await _client!.listRoots();
    if (result.isOk) {
      setState(() {
        _roots = result.unwrap;
        _loading = false;
      });
    } else {
      setState(() {
        _error = result.errorMessage;
        _loading = false;
      });
    }
  }

  void _openRoot(String alias) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            FileManagerScreen(client: _client!, alias: alias, role: _role),
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
        title: Text(widget.hostAddress),
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
                  subtitle: Text('Requires at least: ${root['minimumRole']}'),
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
