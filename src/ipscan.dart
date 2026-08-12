import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:semaphore/semaphore.dart';
import 'config.dart';
import 'libs/http.dart';
import 'libs/ip.dart';
import 'libs/tcping.dart';
import 'util/progress.dart';
import 'util/result.dart';

Future<Map<String, TcpingStats?>> createTcping({
  required List<String> ips,
  int tcpingConcurrency = 64,
  int tcpingPort = 443,
  int tcpingTimes = 4,
  double pingOkThreadhold = 0.5,
  Duration tcpingTimeout = const Duration(milliseconds: 1000),
}) async {
  final Semaphore semaphore = LocalSemaphore(tcpingConcurrency);
  final Map<String, TcpingStats?> results = {};
  final List<Future<void>> tcpingTasks = [];
  int total = ips.length;
  int available = 0;
  int processed = 0;
  for (final String ip in ips) {
    final Future<void> task = Future(() async {
      await semaphore.acquire();
      try {
        final stats = await concurrentMultiTcping(
          ip: ip,
          port: tcpingPort,
          timeout: tcpingTimeout,
          pingTimes: tcpingTimes,
          pingOkThreadhold: pingOkThreadhold,
        );
        results[ip] = stats;
        available++;
      } catch (e) {
        results[ip] = null;
      } finally {
        semaphore.release();
        processed++;
        if (processed % 5 == 0 || processed == total) {
          printProgress(label: "TCPing搜索", processed, total, available);
        }
      }
    });
    tcpingTasks.add(task);
  }
  await Future.wait(tcpingTasks);
  return results;
}

Future<Map<String, ({int statusCode, String? colo})>> createHttpHeadFilter({
  required List<String> ips,
  required String url,
  Duration timeout = const Duration(milliseconds: 1000),
  int concurrency = 16,
  int requireCount = 32,
  List<String> coloRequirements = const [],
  List<int> allowedStatus = const [],
}) async {
  if (ips.isEmpty) {
    return {};
  }
  final semaphore = LocalSemaphore(concurrency);
  final Map<String, ({int statusCode, String? colo})> availableResults = {};
  final completer =
      Completer<Map<String, ({int statusCode, String? colo})>>();

  final int total = ips.length;
  int processed = 0;
  int available = 0;
  for (final String ip in ips) {
    unawaited(
      Future(() async {
        await semaphore.acquire();
        try {
          if (completer.isCompleted || available >= requireCount) {
            return;
          }
          //throwable
          final result = await httpHead(
            url: url,
            anycastIp: ip,
            timeout: timeout,
            allowedStatus: allowedStatus,
          ).timeout(
            timeout,
            onTimeout: () => throw TimeoutException('Response timeout'),
          );
          final String? colo = result.colo;
          if (coloRequirements.isNotEmpty && !coloRequirements.contains(colo)) {
            throw Exception("colo not satisfied");
          }
          availableResults[ip] = (statusCode: result.status, colo: colo);
          available++;
          if (available >= requireCount && !completer.isCompleted) {
            completer.complete(availableResults);
          }
        } catch (e) {
        } finally {
          semaphore.release();
          processed++;
          if (!completer.isCompleted) {
            if (available >= requireCount) {
              completer.complete(availableResults);
            } else if (processed == total) {
              completer.complete(availableResults);
            } else {
              printProgress(processed, total, available, label: "HTTP HEAD");
            }
          }
        }
      }),
    );
  }
  return completer.future.whenComplete(() {
    printProgress(total, total, available, label: "HTTP HEAD");
  });
}

Future<Map<String, ({double speed, String? colo, int ttfb, int statusCode})>>
createDownloadTest({
  required List<String> ips,
  required String url,
  Duration timeout = const Duration(milliseconds: 5000),
  Duration downloadTimeout = const Duration(milliseconds: 100000),
  int maxBytesRead = 1024 * 1024 * 10,
  List<String> coloRequirements = const [],
  List<int> allowedStatus = const [],
  int requireCount = 0,
}) async {
  final Map<String, ({double speed, String? colo, int ttfb, int statusCode})>
  results = {};
  int total = ips.length;
  int available = 0;
  int processed = 0;
  for (final String ip in ips) {
    if (requireCount > 0 && available >= requireCount) break;
    try {
      final result = await httpDownload(
        url: url,
        timeout: timeout,
        downloadTimeout: downloadTimeout,
        anycastIp: ip,
        maxBytesRead: maxBytesRead,
        allowedStatus: allowedStatus,
      );

      final String? colo = result.colo;
      if (coloRequirements.isNotEmpty && !coloRequirements.contains(colo)) {
        throw Exception("colo not satisfied");
      }

      results[ip] = (
        speed: result.speed,
        colo: colo,
        ttfb: result.ttfb,
        statusCode: result.status,
      );
      available++;
    } catch (e) {
    } finally {
      processed++;
      printProgress(processed, total, available, label: "下载测速");
    }
  }
  if (requireCount > 0 && available >= requireCount && processed < total) {
    printProgress(total, total, available, label: "下载测速");
  }
  return results;
}

Future<({List<ResultContainer> allAvailable, List<ResultContainer> result})>
createTrialChambers({
  required List<String> ips,
  int requireCount = 10,
  int httpHeadCountExpand = 10,
  List<String> coloRequirements = const [],
  List<int> allowedStatus = const [200, 201, 301, 302, 307],
  int tcpingConcurrency = 32,
  int tcpingPort = 443,
  int tcpingTimes = 4,
  double pingOkThreadhold = 0.5,
  int httpHeadconcurrency = 16,
  String httpHeadUrl = "https://speedtest.nekocha.top/download",
  String httpDownloadUrl = "https://speed.cloudflare.com/__down?bytes=5242880",
  int maxBytesRead = 1024 * 1024 * 10,
  Duration tcpingTimeout = const Duration(milliseconds: 1000),
  Duration httpHeadTimeout = const Duration(milliseconds: 1000),
  Duration httpDownloadTimeout = const Duration(milliseconds: 5000),
  Duration downloadTimeout = const Duration(milliseconds: 100000),
  bool sortResult = true,
}) async {
  final Map<String, TcpingStats?> tcpingStatsMap = await createTcping(
    ips: ips,
    tcpingConcurrency: tcpingConcurrency,
    tcpingPort: tcpingPort,
    tcpingTimeout: tcpingTimeout,
    tcpingTimes: tcpingTimes,
    pingOkThreadhold: pingOkThreadhold,
  );

  final List<String> okIps = [
    for (final e in tcpingStatsMap.entries)
      if (e.value != null) e.key,
  ];
  if (okIps.isEmpty) {
    return (allAvailable: <ResultContainer>[], result: <ResultContainer>[]);
  }
  okIps.sort((a, b) => tcpingStatsMap[a]!.ping.compareTo(tcpingStatsMap[b]!.ping));

  // *ref result
  final headResultMap = await createHttpHeadFilter(
    ips: okIps,
    url: httpHeadUrl,
    requireCount: requireCount + httpHeadCountExpand,
    allowedStatus: allowedStatus,
    coloRequirements: coloRequirements,
    timeout: httpHeadTimeout,
    concurrency: httpHeadconcurrency,
  );

  final List<String> headPassedIps = headResultMap.keys.toList();
  final downloadResultMap = headPassedIps.isNotEmpty
      ? await createDownloadTest(
          ips: headPassedIps,
          url: httpDownloadUrl,
          maxBytesRead: maxBytesRead,
          allowedStatus: allowedStatus,
          coloRequirements: coloRequirements,
          timeout: httpDownloadTimeout,
          downloadTimeout: downloadTimeout,
          requireCount: requireCount,
        )
      : <String, ({double speed, String? colo, int ttfb, int statusCode})>{};

  final Map<String, ResultContainer> containerMap = {};
  for (final String ip in okIps) {
    final TcpingStats? stats = tcpingStatsMap[ip];
    if (stats == null) continue;
    final ResultContainer container = ResultContainer(ip: ip)
      ..isTcpSuccess = true
      ..tcpingAttempt = stats.attempts
      ..tcpingSuccess = stats.success
      ..ping = stats.ping;

    final head = headResultMap[ip];
    if (head != null) {
      container.isHttpHeadSuccess = true;
      container.httpStatusCode = head.statusCode;
      //有的拿不到colo
      if (head.colo != null) {
        container.colo = head.colo;
      }
    }
    final download = downloadResultMap[ip];
    if (download != null) {
      container.isDownloadSuccess = true;
      container.httpStatusCode = download.statusCode;
      container.speed = download.speed;
      container.httpTTFB = download.ttfb;
      if (container.colo == null && download.colo != null) {
        container.colo = download.colo;
      }
    }
    containerMap[ip] = container;
  }

  final List<ResultContainer> allAvailable =
      [for (final ip in okIps) containerMap[ip]!];
  final List<ResultContainer> available = [
    for (final ip in downloadResultMap.keys) containerMap[ip]!,
  ].take(requireCount).toList();

  if (sortResult) {
    allAvailable.sort((a, b) => b.score.compareTo(a.score));
    available.sort((a, b) => b.score.compareTo(a.score));
  }
  return (allAvailable: allAvailable, result: available);
}

Future<List<String>> readAvailableCacheIps(File file) async {
  try {
    if (await file.exists()) {
      var lines = await file.readAsLines(encoding: utf8);
      lines = lines.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      return lines;
    }
  } catch (e) {}
  return [];
}

Future<void> writeOrUpdateAvailableCacheIps(File file, List<String> ips) async {
  try {
    if (ips.isNotEmpty) {
      await file.writeAsString(ips.join("\n"));
    }
  } catch (e) {}
}

Future<void> writeResultCSV(File file, List<ResultContainer> results) async {
  final String headers = "分数,IP,TCP包数,TCP成功数,丢包,延迟,速度,服务器地区";
  final List<String> csv = [headers];
  for (var r in results) {
    final score = r.score;
    final ip = r.ip;
    final tcpp = r.tcpingAttempt;
    final tcpc = r.tcpingSuccess;
    final loss = r.loss;
    final ping = r.ping;
    final speed = r.speed;
    final colo = r.colo;
    csv.add(
      "${score},${ip},${tcpp},${tcpc},${loss},${ping},${speed},${colo ?? "N/A"}",
    );
  }
  final String csvString = csv.join("\n");
  try {
    await file.writeAsString(csvString, encoding: utf8);
  } catch (e) {}
}

Future<List<ResultContainer>> ipScan(Config config) async {
  final File availableCacheFile = File(
    config.ipv6
        ? config.availableCacheFilePathV6
        : config.availableCacheFilePathV4,
  );
  final File resultFile = File(config.resultPath);

  final Set<String> ipToTest = Set<String>();
  final Set<String> ipAvailableToCache = Set<String>();
  final List<ResultContainer> finalResults = [];
  final List<ResultContainer> allResults = [];

  Future<List<ResultContainer>> createReturnResult() async {
    ipToTest.clear();
    allResults.sort((a, b) => b.score.compareTo(a.score));
    finalResults.sort((a, b) => b.score.compareTo(a.score));
    await writeResultCSV(resultFile, allResults);
    allResults.clear();
    await writeOrUpdateAvailableCacheIps(
      availableCacheFile,
      ipAvailableToCache.toList(),
    );
    return finalResults;
  }

  if (config.useAvailableCache) {
    List<String> availableCacheIps = await readAvailableCacheIps(
      availableCacheFile,
    );
    if (availableCacheIps.isNotEmpty) {
      ipToTest.addAll(availableCacheIps);
      if (availableCacheIps.length >= 100) {
        try {
          final searchResults = await createTrialChambers(
            ips: availableCacheIps,
            requireCount: config.resultCount,
            httpHeadCountExpand: config.httpHeadCountExpand,
            coloRequirements: config.coloRequirements,
            allowedStatus: config.allowedStatus,
            tcpingConcurrency: config.tcpingConcurrency,
            tcpingPort: config.tcpingPort,
            tcpingTimes: config.tcpingTimes,
            pingOkThreadhold: config.pingOkThreadhold,
            httpHeadconcurrency: config.httpHeadConcurrency,
            httpHeadUrl: config.httpHeadUrl,
            httpDownloadUrl: config.httpDownloadUrl,
            maxBytesRead: config.maxBytesRead,
            tcpingTimeout: config.tcpingTimeout,
            httpHeadTimeout: config.httpHeadTimeout,
            httpDownloadTimeout: config.httpDownloadTimeout,
            downloadTimeout: config.downloadTimeout,
            sortResult: false,
          );
          final List<String> availableIps = searchResults.allAvailable
              .map((e) => e.ip)
              .toList();
          if (availableIps.isNotEmpty) {
            ipAvailableToCache.addAll(availableIps);
          }
          finalResults.addAll(searchResults.result);
          allResults.addAll(searchResults.allAvailable);
        } catch (_) {}
      }
    }
  }

  if (finalResults.length >= config.resultCount) {
    return await createReturnResult();
  }

  final int requireSearchCount =
      config.resultCount - finalResults.length;
  final String ipRangeFilePath =
      config.ipv6 ? config.ipv6File : config.ipv4File;
  final File ipRangeFile = File(ipRangeFilePath);
  if (!ipRangeFile.existsSync()) {
    throw Exception("IP范围文件不存在: $ipRangeFilePath");
  }
  final List<String> ipRanges = (await ipRangeFile.readAsLines(encoding: utf8))
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
  if (ipRanges.isEmpty) {
    throw Exception("IP范围文件为空: $ipRangeFilePath");
  }
  final List<String> extractedIps = extractCidr(
    ipRanges,
    maxCountPreSegments: config.maxIpCountPreSegments,
  );
  ipToTest.addAll(extractedIps);

  final searchResults = await createTrialChambers(
    ips: ipToTest.toList(),
    requireCount: requireSearchCount,
    httpHeadCountExpand: config.httpHeadCountExpand,
    coloRequirements: config.coloRequirements,
    allowedStatus: config.allowedStatus,
    tcpingConcurrency: config.tcpingConcurrency,
    tcpingPort: config.tcpingPort,
    tcpingTimes: config.tcpingTimes,
    pingOkThreadhold: config.pingOkThreadhold,
    httpHeadconcurrency: config.httpHeadConcurrency,
    httpHeadUrl: config.httpHeadUrl,
    httpDownloadUrl: config.httpDownloadUrl,
    maxBytesRead: config.maxBytesRead,
    tcpingTimeout: config.tcpingTimeout,
    httpHeadTimeout: config.httpHeadTimeout,
    httpDownloadTimeout: config.httpDownloadTimeout,
    downloadTimeout: config.downloadTimeout,
    sortResult: false,
  );

  final List<String> availableIps = searchResults.allAvailable
      .map((e) => e.ip)
      .toList();
  if (availableIps.isNotEmpty) {
    ipAvailableToCache.addAll(availableIps);
  }
  finalResults.addAll(searchResults.result);
  allResults.addAll(searchResults.allAvailable);

  return await createReturnResult();
}
