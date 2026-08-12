import 'dart:async';
import 'dart:io';
import 'package:semaphore/semaphore.dart';
import 'config.dart';
import 'libs/hosts.dart';
import 'libs/http.dart';
import 'libs/tcping.dart';
import 'util/progress.dart';
import 'util/result.dart';

Future<Map<String, TcpingStats?>> createTcpingCheck({
  required List<String> ips,
  int port = 443,
  Duration timeout = const Duration(milliseconds: 1000),
  int times = 4,
  double okThreshold = 0.5,
  int concurrency = 16,
}) async {
  final Semaphore semaphore = LocalSemaphore(concurrency);
  final Map<String, TcpingStats?> results = {};
  final List<Future<void>> futures = [];
  
  int total = ips.length;
  int current = 0;
  int available = 0;

  for (var ip in ips) {
    futures.add(
      Future(() async {
        await semaphore.acquire();
        try {
          final stats = await concurrentMultiTcping(
            ip: ip,
            timeout: timeout,
            port: port,
            pingTimes: times,
            pingOkThreadhold: okThreshold,
          );
          results[ip] = stats;
          available++;
        } catch (e) {
          results[ip] = null;
        } finally {
          semaphore.release();
          current++;
          printProgress(current, total, available,label: "TCPing检测");
        }
      }),
    );
  }
  await Future.wait(futures, eagerError: false);

  futures.clear();
  return results;
}

Future<Map<String, ({int statusCode, String? colo, double speed, int ttfb})?>>
createHttpCheck({
  required List<String> ips,
  required String httpHeadUrl,
  required String downloadUrl,
  Duration httpHeadTimeout = const Duration(milliseconds: 1000),
  Duration httpDownloadTimeout = const Duration(milliseconds: 1000),
  Duration downloadTimeout = const Duration(milliseconds: 100000),
  int httpHeadConcurrency = 16,
  List<int> allowedStatus = const [200, 201, 301, 302, 307],
  int maxBytesRead = 1024 * 1024 * 10,
}) async {
  final Semaphore httpHeadSemaphore = LocalSemaphore(httpHeadConcurrency);
  final List<Future<void>> httpHeadFutures = [];

  final Map<String, ({int statusCode, String? colo, double speed, int ttfb})?>
  results = {};
  final Set<String> downloadTestIps = {};
  int headTotal = ips.length;
  int headCurrent = 0;
  int headAvailable = 0;
  for (var ip in ips) {
    httpHeadFutures.add(
      Future(() async {
        await httpHeadSemaphore.acquire();
        try {
          final httpHeadResult = await httpHead(
            url: httpHeadUrl,
            timeout: httpHeadTimeout,
            anycastIp: ip,
            allowedStatus: allowedStatus,
          );
          downloadTestIps.add(ip);
          results[ip] = (
            statusCode: httpHeadResult.status,
            speed: 0.0,
            ttfb: 0,
            colo: httpHeadResult.colo,
          );
          headAvailable++;
        } catch (e) {
          results[ip] = null;
        } finally {
          httpHeadSemaphore.release();
          headCurrent++;
          printProgress(
            headCurrent,
            headTotal,
            headAvailable,
            label: "HTTP HEAD",
          );
        }
      }),
    );
  }

  await Future.wait(httpHeadFutures,eagerError: false);

  int downloadTotal = downloadTestIps.length;
  int downloadCurrent = 0;
  int downloadAvailable = 0;
  for (var ip in downloadTestIps) {
    
    try {
      final downloadTestResult = await httpDownload(
        url: downloadUrl,
        timeout: httpDownloadTimeout,
        downloadTimeout: downloadTimeout,
        anycastIp: ip,
        allowedStatus: allowedStatus,
      );
      results[ip] = (
        colo: results[ip]?.colo != null
            ? results[ip]?.colo!
            : downloadTestResult.colo,
        statusCode: downloadTestResult.status,
        speed: downloadTestResult.speed,
        ttfb: downloadTestResult.ttfb,
      );
      downloadAvailable++;
    } catch (e) {
      results[ip] = null;
    } finally {
      downloadCurrent++;
      printProgress(
        downloadCurrent,
        downloadTotal,
        downloadAvailable,
        label: "下载测试",
      );
    }
  }

  downloadTestIps.clear();
  httpHeadFutures.clear();
  return results;
}

Future<Map<String, ResultContainer>> check(Config config) async {
  final File manifestFile = File(config.hostsManifestPath);
  final List<HostActionItem> actionItems =
      await readSystemHostsAndHostsManifestToCreateHostsActionList(
        manifestFile,
      );
  final Map<String, String> hostIpMap = {};
  for (var item in actionItems) {
    if (item.ip != null) {
      hostIpMap[item.host] = item.ip!;
    }
  }
  final List<String> uniqueIps = hostIpMap.values.toSet().toList();
  // ip->stats
  final Map<String, TcpingStats?> tcpingStatsMap = await createTcpingCheck(
    ips: uniqueIps,
    times: config.tcpingTimes,
    okThreshold: config.pingOkThreadhold,
    port: config.tcpingPort,
    concurrency: config.tcpingConcurrency,
    timeout: config.tcpingTimeout,
  );

  final Set<String> httpCheckIps = {};
  for (var e in tcpingStatsMap.entries) {
    final String ip = e.key;
    final TcpingStats? stats = e.value;
    (stats != null) && httpCheckIps.add(ip);
  }
  //http检查
  // ip->stats
  final httpCheckResultMap = await createHttpCheck(
    ips: httpCheckIps.toList(),
    httpHeadUrl: config.httpHeadUrl,
    downloadUrl: config.httpDownloadUrl,
    httpHeadTimeout: config.httpHeadTimeout,
    httpDownloadTimeout: config.httpDownloadTimeout,
    downloadTimeout: config.downloadTimeout,
    httpHeadConcurrency: config.httpHeadConcurrency,
    maxBytesRead: config.maxBytesRead,
    allowedStatus: config.allowedStatus,
  );

  final Map<String, ResultContainer> resultMap = {};
  for (var e in hostIpMap.entries) {
    final String host = e.key;
    final String ip = e.value;
    final TcpingStats? tcpingStats = tcpingStatsMap[ip];
    if (tcpingStats != null) {
      ResultContainer result = ResultContainer(ip: ip)
        ..isTcpSuccess = true
        ..tcpingAttempt = tcpingStats.attempts
        ..tcpingSuccess = tcpingStats.success
        ..ping = tcpingStats.ping;

      final httpCheckResult = httpCheckResultMap[ip];
      if (httpCheckResult != null) {
        result.isHttpHeadSuccess = true;
        result.isDownloadSuccess = true;
        result.httpTTFB = httpCheckResult.ttfb;
        result.httpStatusCode = httpCheckResult.statusCode;
        result.speed = httpCheckResult.speed;
        result.colo = httpCheckResult.colo;
      }
      resultMap[host] = result;
    } else {
      resultMap[host] = ResultContainer.badResult(ip);
    }
  }
  return resultMap;
}
