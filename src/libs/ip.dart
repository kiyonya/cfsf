import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

List<String> extractCidr(List<String> segments, {int maxCountPreSegments = 1}) {
  final rand = Random();
  final result = <String>[];

  for (final rawSeg in segments) {
    final seg = rawSeg.trim();
    if (seg.isEmpty) continue;

    if (seg.contains('.')) {
      final _IPv4CIDR cidr = _parseIPv4CIDR(seg);
      final List<int> network = cidr.network;
      final int prefix = cidr.prefix;
      final totalHosts = (prefix == 32) ? 1 : _ipv4TotalHosts(prefix);

      if (totalHosts <= maxCountPreSegments) {
        for (var i = 0; i < totalHosts; i++) {
          result.add(_ipv4ToString(_offsetToIPv4(network, i)));
        }
      } else {
        final selected = <String>{};
        while (selected.length < maxCountPreSegments) {
          final offset = rand.nextInt(totalHosts);
          selected.add(_ipv4ToString(_offsetToIPv4(network, offset)));
        }
        result.addAll(selected);
      }
    } else {
      final cidr = _parseIPv6CIDR(seg);
      final network = cidr.network;
      final prefix = cidr.prefix;
      int totalHosts;
      if (prefix == 128) {
        totalHosts = 1;
      } else {
        final hostBits = 128 - prefix;
        if (hostBits <= 30) {
          totalHosts = 1 << hostBits;
        } else {
          totalHosts = maxCountPreSegments + 1;
        }
      }

      if (totalHosts <= maxCountPreSegments) {
        for (var i = 0; i < totalHosts; i++) {
          result.add(_ipv6ToString(_offsetToIPv6(network, prefix, i)));
        }
      } else {
        final selected = <String>{};
        while (selected.length < maxCountPreSegments) {
          final ip = _randomIPv6InSubnet(network, prefix, rand);
          selected.add(_ipv6ToString(ip));
        }
        result.addAll(selected);
      }
    }
  }

  return result;
}

_IPv4CIDR _parseIPv4CIDR(String cidr) {
  String ipPart;
  int prefix;
  if (cidr.contains('/')) {
    final parts = cidr.split('/');
    ipPart = parts[0];
    prefix = int.parse(parts[1]);
  } else {
    ipPart = cidr;
    prefix = 32;
  }
  final octets = ipPart.split('.').map(int.parse).toList();
  final network = List<int>.filled(4, 0);
  for (var i = 0; i < 4; i++) {
    network[i] = octets[i];
  }
  _applyIPv4Mask(network, prefix);
  return _IPv4CIDR(network, prefix);
}

int _ipv4TotalHosts(int prefix) => 1 << (32 - prefix);

List<int> _offsetToIPv4(List<int> network, int offset) {
  final ip = List<int>.from(network);
  ip[3] += offset;
  ip[2] += ip[3] ~/ 256;
  ip[3] %= 256;
  ip[1] += ip[2] ~/ 256;
  ip[2] %= 256;
  ip[0] += ip[1] ~/ 256;
  ip[1] %= 256;
  return ip;
}

void _applyIPv4Mask(List<int> ip, int prefix) {
  for (var i = 0; i < 4; i++) {
    final bitsToKeep = (prefix - i * 8).clamp(0, 8);
    final mask = (0xFF << (8 - bitsToKeep)) & 0xFF;
    ip[i] &= mask;
  }
}

String _ipv4ToString(List<int> ip) => ip.join('.');

_IPv6CIDR _parseIPv6CIDR(String cidr) {
  String ipPart;
  int prefix;
  if (cidr.contains('/')) {
    final parts = cidr.split('/');
    ipPart = parts[0];
    prefix = int.parse(parts[1]);
  } else {
    ipPart = cidr;
    prefix = 128;
  }
  final addr = InternetAddress(ipPart, type: InternetAddressType.IPv6);
  final raw = addr.rawAddress;
  final network = List<int>.from(raw, growable: false);
  _applyIPv6Mask(network, prefix);
  return _IPv6CIDR(network, prefix);
}

List<int> _offsetToIPv6(List<int> network, int prefix, int offset) {
  final ip = List<int>.from(network);
  int remaining = offset;
  for (int i = 15; i >= 0; i--) {
    final bitsForThisByte = 8 - (prefix - i * 8).clamp(0, 8);
    if (bitsForThisByte > 0) {
      final mask = (1 << bitsForThisByte) - 1;
      ip[i] = (ip[i] & ~mask) | (remaining & mask);
      remaining >>= bitsForThisByte;
    }
  }
  return ip;
}

List<int> _randomIPv6InSubnet(List<int> network, int prefix, Random rand) {
  final ip = List<int>.from(network);
  for (int i = 15; i >= 0; i--) {
    final bitsForThisByte = 8 - (prefix - i * 8).clamp(0, 8);
    if (bitsForThisByte > 0) {
      final mask = (1 << bitsForThisByte) - 1;
      ip[i] = (ip[i] & ~mask) | (rand.nextInt(1 << bitsForThisByte) & mask);
    }
  }
  return ip;
}

void _applyIPv6Mask(List<int> ip, int prefix) {
  for (var i = 0; i < 16; i++) {
    final bitsToKeep = (prefix - i * 8).clamp(0, 8);
    final mask = (0xFF << (8 - bitsToKeep)) & 0xFF;
    ip[i] &= mask;
  }
}

String _ipv6ToString(List<int> ip) {
  return InternetAddress.fromRawAddress(
    Uint8List.fromList(ip),
    type: InternetAddressType.IPv6,
  ).address;
}

class _IPv4CIDR {
  final List<int> network;
  final int prefix;
  _IPv4CIDR(this.network, this.prefix);
}

class _IPv6CIDR {
  final List<int> network;
  final int prefix;
  _IPv6CIDR(this.network, this.prefix);
}
