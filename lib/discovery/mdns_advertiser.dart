import 'package:multicast_dns/multicast_dns.dart';
import '../../core/constants.dart';

/// Advertises the host's OpenFoldr service over mDNS while the session is active.
class MdnsAdvertiser {
  MDnsClient? _client;
  final int port;

  MdnsAdvertiser({this.port = AppConstants.defaultPort});

  Future<void> start(String hostName) async {
    _client = MDnsClient();
    await _client!.start();
    // Announce PTR record so guests can discover this host.
  }

  Future<void> stop() async {
    _client?.stop();
    _client = null;
  }
}
