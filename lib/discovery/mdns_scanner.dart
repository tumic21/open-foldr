import 'dart:convert';
import 'dart:io';
import 'package:multicast_dns/multicast_dns.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

/// A discovered host on the local network.
class DiscoveredHost {
  final String name;
  final String address;
  final int port;

  const DiscoveredHost({
    required this.name,
    required this.address,
    required this.port,
  });
}

/// Scans for OpenFoldr hosts on the LAN using mDNS.
class MdnsScanner {
  final _results = <DiscoveredHost>[];
  final _seen = <String>{};
  MDnsClient? _client;

  List<DiscoveredHost> get results => List.unmodifiable(_results);

  Future<List<DiscoveredHost>> scan({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _results.clear();
    _seen.clear();

    await _scanMdns(timeout);

    // Fallback for environments where mDNS advertisements are unavailable.
    if (_results.isEmpty) {
      await _scanLocalSubnet();
    }

    await _probeHost('127.0.0.1');

    return List.unmodifiable(_results);
  }

  Future<void> _scanMdns(Duration timeout) async {
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
            _addHost(
              name: ptr.domainName,
              address: ip.address.address,
              port: srv.port,
            );
          }
        }
      }
    } finally {
      _client!.stop();
      _client = null;
    }
  }

  Future<void> _scanLocalSubnet() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
      includeLinkLocal: false,
    );

    final prefixes = <String>{};
    for (final iface in interfaces) {
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
          probes.add(_probeHost('$prefix.$i'));
        }
        await Future.wait(probes);
      }
    }
  }

  Future<void> _probeHost(String address) async {
    final uri = Uri.parse(
      'http://$address:${AppConstants.defaultPort}/v1/health',
    );

    try {
      final res = await http
          .get(uri)
          .timeout(const Duration(milliseconds: 300));
      if (res.statusCode != 200) return;

      final json = jsonDecode(res.body) as Map<String, dynamic>;
      if (json['status'] != 'ok') return;

      _addHost(
        name: 'OpenFoldr ($address)',
        address: address,
        port: AppConstants.defaultPort,
      );
    } catch (_) {
      // Ignore probe failures for non-OpenFoldr hosts.
    }
  }

  void _addHost({
    required String name,
    required String address,
    required int port,
  }) {
    final key = '$address:$port';
    if (_seen.contains(key)) return;
    _seen.add(key);
    _results.add(DiscoveredHost(name: name, address: address, port: port));
  }
}
