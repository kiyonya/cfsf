import 'dart:async';
import 'package:chalkdart/chalkstrings.dart';
import 'package:semaphore/semaphore.dart';
import 'libs/tcping.dart';
import 'util/ip.dart';
import 'util/progress.dart';

List<BigInt> createRangeProbeSamples({
  required BigInt start,
  required BigInt end,
  required int sampleGap,
}) {
  final gap = sampleGap < 1 ? 1 : sampleGap;
  final result = <BigInt>[];
  for (BigInt ip = start; ip <= end; ip += BigInt.from(gap)) {
    result.add(ip);
  }
  if (result.isEmpty) {
    result.add(end);
  } else if (result.last != end) {
    result.add(end);
  }
  return result;
}

Future<List<String>> refineIpCidrSegment(
  String cidr, {
  bool ipv6 = false,
  required int initialSampleGap,
  required int iterations,
  int radius = 100,
  int port = 443,
  Duration timeout = const Duration(milliseconds: 1000),
  int pingTimes = 4,
  double pingOkThreadhold = 0.5,
  int concurrency = 64,
  void Function(int processed, int total, int ok)? onProgress,
}) async {
  final parent = openCidrRange(cidr, ipv6: ipv6);
  var ranges = <({BigInt start, BigInt end})>[
    (start: parent.start, end: parent.end),
  ];
  var gap = initialSampleGap < 1 ? 1 : initialSampleGap;

  for (var iter = 0; iter < iterations; iter++) {
    final samples = <({BigInt value, BigInt parentStart, BigInt parentEnd})>[];
    for (final r in ranges) {
      for (final s in createRangeProbeSamples(
        start: r.start,
        end: r.end,
        sampleGap: gap,
      )) {
        samples.add((value: s, parentStart: r.start, parentEnd: r.end));
      }
    }
    if (samples.isEmpty) break;

    print("轮次 ${(iter+1).toString().bold.green},本轮探测 ${samples.length.toString().green.bold} 个IP".bold.aqua);
    final okSet = await createTcpingProbe(
      samples.map((e) => e.value).toList(),
      ipv6: ipv6,
      port: port,
      timeout: timeout,
      pingTimes: pingTimes,
      pingOkThreadhold: pingOkThreadhold,
      concurrency: concurrency,
      onProgress: (processed, total, ok) => onProgress?.call(
        processed,
        total,
        ok,
      ),
    );

    final newRanges = <({BigInt start, BigInt end})>[];
    for (final s in samples) {
      if (!okSet.contains(s.value)) continue;
      final r = BigInt.from(radius);
      var lo = s.value - r;
      var hi = s.value + r;
      if (lo < s.parentStart) lo = s.parentStart;
      if (hi > s.parentEnd) hi = s.parentEnd;
      newRanges.add((start: lo, end: hi));
    }
    ranges = mergeRanges(newRanges);
    if (ranges.isEmpty) break;
    gap = (gap / 10).ceil();
    if (gap < 1) gap = 1;
  }

  final result = <String>[];
  for (final r in ranges) {
    result.addAll(rangeToCidrs(r.start, r.end, ipv6: ipv6));
  }
  return result;
}

Future<Set<BigInt>> createTcpingProbe(
  List<BigInt> ips, {
  required bool ipv6,
  required int port,
  required Duration timeout,
  required int pingTimes,
  required double pingOkThreadhold,
  required int concurrency,
  void Function(int processed, int total, int ok)? onProgress,
}) async {
  final semaphore = LocalSemaphore(concurrency);
  final ok = <BigInt>{};
  final tasks = <Future<void>>[];

int total = ips.length;
 int current = 0;
 int available = 0;

  for (final ip in ips) {
    tasks.add(
      Future(() async {
        await semaphore.acquire();
        try {
          await concurrentMultiTcping(
            ip: bigIntToIp(ip, ipv6: ipv6),
            port: port,
            timeout: timeout,
            pingTimes: pingTimes,
            pingOkThreadhold: pingOkThreadhold,
          );
          ok.add(ip);
          available++;
        } catch (_) {
        } finally {
          semaphore.release();
          current++;
          printProgress(current, total, available);
        }
      }),
    );
  }
  await Future.wait(tasks);
  return ok;
}

List<({BigInt start, BigInt end})> mergeRanges(
  List<({BigInt start, BigInt end})> ranges,
) {
  final sorted = [...ranges]..sort((a, b) => a.start.compareTo(b.start));
  final result = <({BigInt start, BigInt end})>[];
  for (final r in sorted) {
    if (result.isEmpty) {
      result.add(r);
      continue;
    }
    final last = result.last;
    if (r.start <= last.end + BigInt.one) {
      if (r.end > last.end) {
        result[result.length - 1] = (start: last.start, end: r.end);
      }
    } else {
      result.add(r);
    }
  }
  return result;
}
