import 'dart:async';
import 'dart:io';

class TcpingStats {
  final String ip;
  final int attempts;
  final int success;
  final double ping;

  TcpingStats({
    required this.ip,
    required this.attempts,
    required this.success,
    required this.ping,
  });
}

Future<double> tcping({
  required String ip,
  int port = 443,
  required Duration timeout,
}) async {
  Socket? connection;
  final int startTime = DateTime.now().millisecondsSinceEpoch;
  try {
    connection = await Socket.connect(ip, port, timeout: timeout);
    final int endTime = DateTime.now().millisecondsSinceEpoch;
    return (endTime - startTime).toDouble();
  } finally {
    if (connection != null) {
      connection.destroy();
      connection = null;
    }
  }
}

/**
 * throwable
 */
Future<TcpingStats> concurrentMultiTcping({
  required String ip,
  int port = 443,
  required Duration timeout,
  int pingTimes = 4,
  double pingOkThreadhold = 0.5,
}) async {
  final int requiredSuccess =
      (pingTimes * pingOkThreadhold).ceil().clamp(1, pingTimes);
  int successCount = 0;
  int attempts = 0;
  double totalPing = 0.0;

  for (int i = 0; i < pingTimes; i++) {
    try {
      final double ping = await tcping(ip: ip, port: port, timeout: timeout);
      successCount++;
      totalPing += ping;
    } catch (_) {
    } finally {
      attempts++;
    }
    if (successCount >= requiredSuccess) break;
    if (successCount + (pingTimes - attempts) < requiredSuccess) break;
  }

  if (successCount < requiredSuccess) {
    throw Exception("tcping failed");
  }
  return TcpingStats(
    ip: ip,
    attempts: attempts,
    success: successCount,
    ping: totalPing / successCount,
  );
}
