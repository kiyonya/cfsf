import 'dart:io';
import 'dart:typed_data';

({BigInt start, BigInt end}) openCidrRange(String ipcidr, {bool ipv6 = false}) {
  final parts = ipcidr.split('/');
  final ipPart = parts[0];
  final int prefix;
  if (parts.length == 2) {
    prefix = int.parse(parts[1]);
  } else {
    prefix = ipv6 ? 128 : 32;
  }

  if (ipv6) {
    if (prefix < 0 || prefix > 128) {
      throw ArgumentError('IPv6 前缀不合法: $prefix');
    }
    final addr = InternetAddress(ipPart, type: InternetAddressType.IPv6);
    final raw = addr.rawAddress;
    BigInt value = BigInt.zero;
    for (final byte in raw) {
      value = (value << 8) | BigInt.from(byte);
    }
    final hostBits = 128 - prefix;
    final hostMask = hostBits == 128
        ? (BigInt.one << 128) - BigInt.one
        : (BigInt.one << hostBits) - BigInt.one;
    final start = value & ~hostMask;
    final end = start | hostMask;
    return (start: start, end: end);
  } else {
    if (prefix < 0 || prefix > 32) {
      throw ArgumentError('IPv4 前缀不合法: $prefix');
    }
    final octets = ipPart.split('.').map(int.parse).toList();
    if (octets.length != 4) {
      throw ArgumentError('IPv4 地址不合法: $ipPart');
    }
    BigInt value = BigInt.zero;
    for (final octet in octets) {
      value = (value << 8) | BigInt.from(octet);
    }
    final hostBits = 32 - prefix;
    final hostMask = hostBits == 32
        ? (BigInt.one << 32) - BigInt.one
        : (BigInt.one << hostBits) - BigInt.one;
    final start = value & ~hostMask & ((BigInt.one << 32) - BigInt.one);
    final end = start | hostMask;
    return (start: start, end: end);
  }
}

List<String> rangeToCidrs(BigInt start, BigInt end, {required bool ipv6}) {
  final totalBits = ipv6 ? 128 : 32;
  final maxAddr = (BigInt.one << totalBits) - BigInt.one;
  if (end > maxAddr) end = maxAddr;
  final result = <String>[];
  var current = start;
  while (current <= end) {
    final remaining = end - current + BigInt.one;
    var k = 0;
    var t = current;
    while ((t & BigInt.one) == BigInt.zero && k < totalBits) {
      k++;
      t >>= 1;
    }
    while (k > 0 && (BigInt.one << k) > remaining) {
      k--;
    }
    final prefix = totalBits - k;
    result.add('${bigIntToIp(current, ipv6: ipv6)}/$prefix');
    current += BigInt.one << k;
  }
  return result;
}

BigInt ipToBigInt(String ip, {bool ipv6 = false}) {
  if (ipv6) {
    final raw = InternetAddress(ip, type: InternetAddressType.IPv6).rawAddress;
    BigInt value = BigInt.zero;
    for (final byte in raw) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }
  final octets = ip.split('.').map(int.parse).toList();
  BigInt value = BigInt.zero;
  for (final octet in octets) {
    value = (value << 8) | BigInt.from(octet);
  }
  return value;
}

String bigIntToIp(BigInt value, {bool ipv6 = false}) {
  if (ipv6) {
    final bytes = Uint8List(16);
    for (var i = 15; i >= 0; i--) {
      bytes[i] = (value & BigInt.from(0xFF)).toInt();
      value >>= 8;
    }
    return InternetAddress.fromRawAddress(
      bytes,
      type: InternetAddressType.IPv6,
    ).address;
  }
  final octets = List<int>.filled(4, 0);
  for (var i = 3; i >= 0; i--) {
    octets[i] = (value & BigInt.from(0xFF)).toInt();
    value >>= 8;
  }
  return octets.join('.');
}
