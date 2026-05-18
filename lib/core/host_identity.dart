import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Stable local host identity used for LAN discovery labels and de-duplication.
class HostIdentity {
  HostIdentity._();

  static final String _seed = _buildSeed();
  static final String id = sha256.convert(utf8.encode(_seed)).toString();
  static final String name = _buildFriendlyName(id);

  static String _buildSeed() {
    final host = Platform.localHostname.trim();
    final user =
        (Platform.environment['USER'] ?? Platform.environment['USERNAME'] ?? '')
            .trim();
    return '$host|$user';
  }

  static String _buildFriendlyName(String hash) {
    const adjectives = [
      'Amber',
      'Brisk',
      'Calm',
      'Clever',
      'Coral',
      'Cosmic',
      'Crisp',
      'Daring',
      'Echo',
      'Emerald',
      'Frost',
      'Gentle',
      'Golden',
      'Harbor',
      'Ivy',
      'Jolly',
      'Kind',
      'Lunar',
      'Maple',
      'Mint',
      'Nimbus',
      'Olive',
      'Pebble',
      'Quiet',
      'Rapid',
      'River',
      'Sable',
      'Silver',
      'Sunny',
      'Tidy',
      'Velvet',
      'Willow',
    ];

    const nouns = [
      'Badger',
      'Beacon',
      'Birch',
      'Brook',
      'Cedar',
      'Cloud',
      'Comet',
      'Dolphin',
      'Falcon',
      'Fern',
      'Field',
      'Firefly',
      'Forest',
      'Galaxy',
      'Harbor',
      'Hill',
      'Island',
      'Lantern',
      'Maple',
      'Meadow',
      'Otter',
      'Pine',
      'Quartz',
      'Ridge',
      'Robin',
      'Shore',
      'Spruce',
      'Star',
      'Summit',
      'Valley',
      'Wave',
      'Wren',
    ];

    final a = int.parse(hash.substring(0, 8), radix: 16);
    final b = int.parse(hash.substring(8, 16), radix: 16);
    final suffix = 100 + (int.parse(hash.substring(16, 20), radix: 16) % 900);

    final adjective = adjectives[a % adjectives.length];
    final noun = nouns[b % nouns.length];
    return '$adjective $noun $suffix';
  }
}
