// import 'dart:async';
// import 'dart:io';

// import 'package:semaphore/semaphore.dart';

// import 'config.dart';
// import 'libs/hosts.dart';
// import 'libs/http.dart';
// import 'libs/tcping.dart';
// import 'util/progress.dart';
// import 'util/result.dart';

// Future<ResultContainer> createConnectionCheck({
//   required String host,
//   int tcpingPort = 443,
//   required String fkHttpHeadUrl,
//   required String fkHttpDownloadUrl,
//   Duration tcpingTimeout = const Duration(milliseconds: 1000),
//   Duration httpHeadTimeout = const Duration(milliseconds: 5000),
//   int tcpingTimes = 4,
//   double pingOkThreadhold = 0.5,
//   StatusValidator? statusValidator,
//   bool performTcping = true, 
// }) async {
//   final ResultContainer result = ResultContainer(ip: host);
//   try {
//     if (performTcping) {
//       final TcpingStats stats = await concurrentMultiTcping(
//         ip: host,
//         timeout: tcpingTimeout,
//         port: tcpingPort,
//         pingTimes: tcpingTimes,
//         pingOkThreadhold: pingOkThreadhold,
//       );
//       result.tcpingAttempt = stats.attempts;
//       result.tcpingSuccess = stats.successCount;
//       result.isTcpSuccess = stats.ok;
//       result.ping = stats.avgPing;
//     } else {
//       result.isTcpSuccess = true;
//       result.tcpingAttempt = 0;
//       result.tcpingSuccess = 0;
//       result.ping = 0;
//     }

//     final httpHeadResult =
//         await httpHead(
//           url: fkHttpHeadUrl,
//           anycastIp: host,
//           timeout: httpHeadTimeout,
//           statusValidator: statusValidator,
//         ).timeout(
//           httpHeadTimeout,
//           onTimeout: () => throw TimeoutException('Response timeout'),
//         );

//     result.colo = httpHeadResult.colo;
//     result.httpStatusCode = httpHeadResult.status;
//     result.isHttpHeadSuccess = true;
//     return result;
//   } catch (e) {
//     rethrow;
//   }
// }

// Future<Map<String, ResultContainer>> concurrencyCheckConnection({
//   required List<String> ips,
//   required String fkHttpHeadUrl,
//   required String fkHttpDownloadUrl,
//   int concurrency = 16,
//   bool useHttps = true,
//   Duration tcpingTimeout = const Duration(milliseconds: 1000),
//   Duration httpHeadTimeout = const Duration(milliseconds: 5000),
//   Duration httpDownloadTimeout = const Duration(milliseconds: 5000),
//   int maxBytesRead = 1024 * 1024 * 10,
//   int tcpingTimes = 4,
//   double pingOkThreadhold = 0.5,
//   StatusValidator? statusValidator,
//   bool performTcping = true, 
// }) async {
//   final Semaphore semaphore = LocalSemaphore(concurrency);
//   final List<Future<void>> futures = [];
//   final Map<String, ResultContainer> resultMap = {};
//   final List<ResultContainer> resultsNeedDownloadTest = [];
//   int total = ips.length;
//   int current = 0;
//   int available = 0;

//   for (final ip in ips) {
//     final task = Future(() async {
//       await semaphore.acquire();
//       try {
//         final ResultContainer result = await createConnectionCheck(
//           host: ip,
//           tcpingTimeout: tcpingTimeout,
//           httpHeadTimeout: httpHeadTimeout,
//           tcpingTimes: tcpingTimes,
//           pingOkThreadhold: pingOkThreadhold,
//           statusValidator: statusValidator,
//           fkHttpDownloadUrl: fkHttpDownloadUrl,
//           fkHttpHeadUrl: fkHttpHeadUrl,
//           performTcping: performTcping, // 传递
//         );
//         result.ip = ip;
//         resultMap[ip] = result;
//         resultsNeedDownloadTest.add(result);
//         available++;
//       } catch (e) {
//         resultMap[ip] = ResultContainer.badResult(ip);
//       } finally {
//         semaphore.release();
//         current++;
//         printProgress(current, total, available,
//             label: performTcping ? "连接状态检测" : "HTTP头检测");
//       }
//     });
//     futures.add(task);
//   }
//   await Future.wait(futures, eagerError: false);

//   int downloadTotal = resultsNeedDownloadTest.length;
//   int downloadAvailable = 0;
//   int downloadCurrent = 0;
//   for (final r in resultsNeedDownloadTest) {
//     try {
//       final String ip = r.ip;
//       final downloadResult = await httpDownload(
//         url: fkHttpDownloadUrl,
//         timeout: httpDownloadTimeout,
//         anycastIp: ip,
//         maxBytesRead: maxBytesRead,
//         statusValidator: statusValidator,
//       );
//       r.httpTTFB = downloadResult.ttfb;
//       r.speed = downloadResult.speed; 
//       if (r.colo == null && downloadResult.colo != null) {
//         r.colo = downloadResult.colo;
//       }
//       r.isDownloadSuccess = true;
//       downloadAvailable++;
//     } catch (e) {
//     } finally {
//       downloadCurrent++;
//       printProgress(
//         downloadCurrent,
//         downloadTotal,
//         downloadAvailable,
//         label: "下载测试",
//       );
//     }
//   }

//   return resultMap;
// }

// Future<Map<String, ResultContainer>> concurrentTcpingHosts({
//   required List<String> hosts,
//   int port = 443,
//   Duration timeout = const Duration(milliseconds: 1000),
//   int times = 4,
//   double okThreshold = 0.5,
//   int concurrency = 16,
// }) async {
//   final Semaphore semaphore = LocalSemaphore(concurrency);
//   final Map<String, ResultContainer> results = {};
//   final List<Future<void>> futures = [];
//   int total = hosts.length;
//   int current = 0;
//   int available = 0;

//   for (final host in hosts) {
//     futures.add(Future(() async {
//       await semaphore.acquire();
//       try {
//         final stats = await concurrentMultiTcping(
//           ip: host, 
//           timeout: timeout,
//           port: port,
//           pingTimes: times,
//           pingOkThreadhold: okThreshold,
//         );
//         results[host] = ResultContainer.fromTcping(
//           ip: host,
//           tcpingAttempt: stats.attempts,
//           tcpingSuccess: stats.successCount,
//           isTcpSuccess: stats.ok,
//           ping: stats.avgPing,
//         );
//         if (stats.ok) available++;
//       } catch (e) {
//         results[host] = ResultContainer.badResult(host);
//       } finally {
//         semaphore.release();
//         current++;
//         printProgress(current, total, available, label: "主机 TCPing");
//       }
//     }));
//   }
//   await Future.wait(futures, eagerError: false);
//   return results;
// }

// Future<Map<String, ResultContainer>> check() async {
//   final Map<String, dynamic> config = getConfig();

//   final String fkHttpHeadUrl = "https://speedtest.nekocha.top/download";
//   final String fkHttpDownloadUrl =
//       "https://speed.cloudflare.com/__down?bytes=5242880";

//   final String manifestFilePath =
//       config['hosts_manifest'] ?? "hosts_manifest.txt";
//   final File manifestFile = File(manifestFilePath);
//   final actionItems =
//       await readSystemHostsAndHostsManifestToCreateHostsActionList(
//         manifestFile,
//       );

//   StatusValidator statusValidator = ({headers, required statusCode}) {
//     return statusCode < 400;
//   };

//   final Map<String, String> host2ip = {};
//   final Set<String> ipSet = {};
//   for (var item in actionItems) {
//     if (item.ip != null) {
//       host2ip[item.host] = item.ip!;
//       ipSet.add(item.ip!);
//     }
//   }

//   final Map<String, ResultContainer> hostTcpingMap = await concurrentTcpingHosts(
//     hosts: host2ip.keys.toList(),
//     timeout: const Duration(milliseconds: 1000),
//     times: 4,
//     okThreshold: 0.5,
//   );

//   final Map<String, ResultContainer> ip2HttpResult =
//       await concurrencyCheckConnection(
//     ips: ipSet.toList(),
//     fkHttpHeadUrl: fkHttpHeadUrl,
//     fkHttpDownloadUrl: fkHttpDownloadUrl,
//     statusValidator: statusValidator,
//     performTcping: false,
//   );

//   final Map<String, ResultContainer> host2Result = {};
//   for (var entry in host2ip.entries) {
//     final host = entry.key;
//     final ip = entry.value;

//     final ResultContainer tcpResult = hostTcpingMap[host]!;
//     final ResultContainer? httpResult = ip2HttpResult[ip];
//     final ResultContainer combined = ResultContainer(ip: host);

//     combined.isTcpSuccess = tcpResult.isTcpSuccess;
//     combined.tcpingAttempt = tcpResult.tcpingAttempt;
//     combined.tcpingSuccess = tcpResult.tcpingSuccess;
//     combined.ping = tcpResult.ping;

//     if (httpResult != null && httpResult.isHttpHeadSuccess && httpResult.isDownloadSuccess) {
//       combined.ip = ip;
//       combined.isHttpHeadSuccess = true;
//       combined.isDownloadSuccess = true;
//       combined.httpStatusCode = httpResult.httpStatusCode;
//       combined.colo = httpResult.colo;
//       combined.httpTTFB = httpResult.httpTTFB;
//       combined.speed = httpResult.speed;
//     } else {
//       combined.isHttpHeadSuccess = false;
//       combined.isHttpHeadSuccess = false;
//     }
//     host2Result[host] = combined;
//   }
//   hostTcpingMap.clear();
//   ip2HttpResult.clear();
//   return host2Result;
// }