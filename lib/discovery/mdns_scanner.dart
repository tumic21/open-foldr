import 'package:multicast_dns/multicast_dns.dart';
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
  MDnsClient? _client;

  List<DiscoveredHost> get results => List.unmodifiable(_results);

  Future<List<DiscoveredHost>> scan({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    _results.clear();
    _client = MDnsClient();
    await _client!.start();

    await for (final PtrResourceRecord ptr in _client!
        .lookup<PtrResourceRecord>(
          ResourceRecordQuery.serverPointer(AppConstants.mdnsServiceType),
        )
        .timeout(timeout, onTimeout: (_) {})) {
      await for (final SrvResourceRecord srv in _client!
          .lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
          )
          .timeout(const Duration(seconds: 2), onTimeout: (_) {})) {
        await for (final IPAddressResourceRecord ip in _client!
            .lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
            )
            .timeout(const Duration(seconds: 2), onTimeout: (_) {})) {
          _results.add(DiscoveredHost(
            name: ptr.domainName,
            address: ip.address.address,
            port: srv.port,
          ));
        }
      }
    }

    _client!.stop();
    _client = null;
    return List.unmodifiable(_results);
  }
}
