import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:multicast_dns/multicast_dns.dart';

import '../core/constants.dart';

/// A discovered host on the local network.
class DiscoveredHost {
  final String hostId;
  final String name;
  final String address;
  final int port;

  const DiscoveredHost({
    required this.hostId,
    required this.name,
    required this.address,
    required this.port,
  });
}

/// Scans for OpenFoldr hosts on the LAN using mDNS.
class MdnsScanner {
  final _results = <DiscoveredHost>[];
  final _seenEndpoints = <String>{};
  MDnsClient? _client;

  List<DiscoveredHost> get results => List.unmodifiable(_results);

  Future<List<DiscoveredHost>> scan({
    Duration timeout = const Duration(seconds: 5),
    void Function(List<DiscoveredHost>)? onUpdate,
  }) async {
    _results.clear();
    _seenEndpoints.clear();

    await _scanMdns(timeout, onUpdate: onUpdate);

    // Fallback for environments where mDNS advertisements are unavailable.
    if (_results.isEmpty) {
      await _scanLocalSubnet(onUpdate: onUpdate);
    }

    // Helpful for same-machine testing when no LAN host is discovered.
    if (_results.isEmpty) {
      await _probeHost('127.0.0.1', onUpdate: onUpdate);
    }

    return List.unmodifiable(_results);
  }

  Future<void> _scanMdns(
    Duration timeout, {
    void Function(List<DiscoveredHost>)? onUpdate,
  }) async {
    _client = MDnsClient();
    await _client!.start();

    try {
      await for (final PtrResourceRecord ptr
          in _client!
              .lookup<PtrResourceRecord>(
                ResourceRecordQuery.serverPointer(AppConstants.mdnsServiceType),
              )
              .timeout(timeout, onTimeout: (_) {})) {
        await for (final SrvResourceRecord srv
            in _client!
                .lookup<SrvResourceRecord>(
                  ResourceRecordQuery.service(ptr.domainName),
                )
                .timeout(const Duration(seconds: 2), onTimeout: (_) {})) {
          await for (final IPAddressResourceRecord ip
              in _client!
                  .lookup<IPAddressResourceRecord>(
                    ResourceRecordQuery.addressIPv4(srv.target),
                  )
                  .timeout(const Duration(seconds: 2), onTimeout: (_) {})) {
            final address = ip.address.address;
            final added = await _probeHost(
              address,
              onUpdate: onUpdate,
              fallbackName: _normalizeMdnsName(ptr.domainName),
              fallbackPort: srv.port,
            );
            if (!added) {
              _upsertHost(
                DiscoveredHost(
                  hostId: '$address:${srv.port}',
                  name: _normalizeMdnsName(ptr.domainName),
                  address: address,
                  port: srv.port,
                ),
                onUpdate: onUpdate,
              );
            }
          }
        }
      }
    } finally {
      _client!.stop();
      _client = null;
    }
  }

  Future<void> _scanLocalSubnet({
    void Function(List<DiscoveredHost>)? onUpdate,
  }) async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

    final prefixes = <String>{};
    for (final iface in interfaces) {
      if (_isVirtualInterface(iface.name)) continue;
      for (final addr in iface.addresses) {
        final parts = addr.address.split('.');
        if (parts.length != 4) continue;
        prefixes.add('${parts[0]}.${parts[1]}.${parts[2]}');
      }
    }

    for (final prefix in prefixes) {
      const batchSize = 24;
      for (var start = 1; start <= 254; start += batchSize) {
        final end = (start + batchSize - 1).clamp(1, 254);
        final probes = <Future<void>>[];
        for (var i = start; i <= end; i++) {
          probes.add(_probeHost('$prefix.$i', onUpdate: onUpdate));
        }
        await Future.wait(probes);
      }
    }
  }

  Future<bool> _probeHost(
    String address, {
    void Function(List<DiscoveredHost>)? onUpdate,
    String? fallbackName,
    int fallbackPort = AppConstants.defaultPort,
  }) async {
    final uri = Uri.parse(
      'http://$address:${AppConstants.defaultPort}/v1/health',
    );

    try {
      final res = await http
          .get(uri)
          .timeout(const Duration(milliseconds: 300));
      if (res.statusCode != 200) return false;

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['status'] != 'ok') return false;

      final host = json['host'] as Map<String, dynamic>?;
      final hostId = (host?['id'] as String?) ?? '$address:$fallbackPort';
      final hostName =
          (host?['name'] as String?) ?? fallbackName ?? 'OpenFoldr';

      _upsertHost(
        DiscoveredHost(
          hostId: hostId,
          name: hostName,
          address: address,
          port: AppConstants.defaultPort,
        ),
        onUpdate: onUpdate,
      );
      return true;
    } catch (_) {
      // Allow mDNS fallback entry if health probe fails.
      if (fallbackName != null) {
        _upsertHost(
          DiscoveredHost(
            hostId: '$address:$fallbackPort',
            name: fallbackName,
            address: address,
            port: fallbackPort,
          ),
          onUpdate: onUpdate,
        );
      }
      return false;
    }
  }

  void _upsertHost(
    DiscoveredHost host, {
    void Function(List<DiscoveredHost>)? onUpdate,
  }) {
    final endpoint = '${host.address}:${host.port}';
    if (_seenEndpoints.contains(endpoint)) return;
    _seenEndpoints.add(endpoint);

    final existingIndex = _results.indexWhere((h) => h.hostId == host.hostId);
    if (existingIndex >= 0) {
      final existing = _results[existingIndex];
      if (_addressScore(host.address) > _addressScore(existing.address)) {
        _results[existingIndex] = host;
        onUpdate?.call(List.unmodifiable(_results));
      }
      return;
    }

    _results.add(host);
    onUpdate?.call(List.unmodifiable(_results));
  }

  static String _normalizeMdnsName(String raw) {
    final first = raw.split('.').first;
    return first.isEmpty ? 'OpenFoldr' : first;
  }

  static bool _isVirtualInterface(String name) {
    final lowered = name.toLowerCase();
    const prefixes = ['docker', 'br-', 'veth', 'virbr', 'podman', 'lo'];
    return prefixes.any(lowered.startsWith);
  }

  static int _addressScore(String address) {
    if (address == '127.0.0.1') return 0;
    if (address.startsWith('172.17.') ||
        address.startsWith('172.18.') ||
        address.startsWith('172.19.') ||
        address.startsWith('172.20.') ||
        address.startsWith('172.21.') ||
        address.startsWith('172.22.') ||
        address.startsWith('172.23.') ||
        address.startsWith('172.24.') ||
        address.startsWith('172.25.') ||
        address.startsWith('172.26.') ||
        address.startsWith('172.27.') ||
        address.startsWith('172.28.') ||
        address.startsWith('172.29.') ||
        address.startsWith('172.30.') ||
        address.startsWith('172.31.')) {
      return 1;
    }
    if (address.startsWith('10.') || address.startsWith('192.168.')) return 3;
    return 2;
  }
}
