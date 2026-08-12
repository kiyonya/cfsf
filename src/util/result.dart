import 'dart:math';

class ResultContainer {
  String ip;

  double? ping;
  int? tcpingAttempt;
  int? tcpingSuccess;
  int? httpStatusCode;
  int? httpTTFB;
  String? colo;
  double? speed;
  bool isTcpSuccess = false;
  bool isHttpHeadSuccess = false;
  bool isDownloadSuccess = false;
  double? _score;

  ResultContainer({required this.ip});

  bool get ok {
    return isTcpSuccess && isHttpHeadSuccess && isDownloadSuccess;
  }

  double get loss {
    if (tcpingAttempt != null && tcpingSuccess != null) {
      return (tcpingAttempt! - tcpingSuccess!) / tcpingAttempt!;
    }
    return 0.0;
  }

  double get score {
    if(_score != null){return _score!;}
    if (ping != null &&
        speed != null &&
        tcpingAttempt != null &&
        tcpingSuccess != null) {
      final latencyMs = max(0, ping!);
      final speedBps = max(0, speed!);
      final loss = this.loss.clamp(0.0, 1.0);
      double speedScore;
      if (speedBps <= 0) {
        speedScore = 0;
      } else {
        const minSpeed = 10 * 1024;
        const maxSpeed = 10 * 1024 * 1024;
        final minSpeedLog = log(minSpeed + 1) / ln10;
        final maxSpeedLog = log(maxSpeed + 1) / ln10;
        final currentSpeedLog = log(speedBps + 1) / ln10;
        double normalized =
            (currentSpeedLog - minSpeedLog) / (maxSpeedLog - minSpeedLog);
        normalized = normalized.clamp(0.0, 1.0);
        speedScore = normalized * 100;
      }
      double latencyScore;
      if (latencyMs <= 50) {
        latencyScore = 100;
      } else if (latencyMs >= 300) {
        latencyScore = 0;
      } else {
        latencyScore = 100 * (1 - (latencyMs - 50) / (300 - 50));
      }

      double lossFactor;
      if (loss <= 0.05) {
        lossFactor = 1.0;
      } else if (loss <= 0.30) {
        lossFactor = 1.0 - (loss - 0.05) * 1.4;
      } else if (loss <= 0.60) {
        lossFactor = 0.65 - (loss - 0.30) * 1.5;
      } else {
        lossFactor = max(0, 0.20 - (loss - 0.60) * 2);
      }

      final baseScore = (speedScore * 0.7) + (latencyScore * 0.3);
      double finalScore = (baseScore * lossFactor).clamp(0.0, 100.0);
      finalScore = (finalScore * 100).roundToDouble() / 100;

      _score = finalScore;
      return finalScore;
    }
    return 0.0;
  }

  static ResultContainer badResult(String ip) {
    final result = ResultContainer(ip: ip);
    result.isTcpSuccess = false;
    result.isHttpHeadSuccess = false;
    return result;
  }

  static ResultContainer fromTcping({
    required String ip,
    required int tcpingAttempt,
    required int tcpingSuccess,
    required bool isTcpSuccess,
    double? ping,
  }) {
    return ResultContainer(ip: ip)
      ..tcpingAttempt = tcpingAttempt
      ..tcpingSuccess = tcpingSuccess
      ..isTcpSuccess = isTcpSuccess
      ..ping = ping;
  }
}
