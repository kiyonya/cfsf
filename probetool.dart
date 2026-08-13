import 'dart:io';

import 'package:args/args.dart';
import 'package:chalkdart/chalkstrings.dart';
import 'src/ipprobe.dart';
import 'src/util/ip.dart';

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'cidr',
      help: 'IP address ranges, comma-separated, e.g. 104.16.0.0/16,1.1.1.0/24',
    )
    ..addOption(
      'input',
      abbr: 'i',
      help: 'Address range file (newline-separated). Overrides --cidr.',
    )
    ..addOption(
      'output',
      abbr: 'o',
      help: 'Output file path for results',
      defaultsTo: "probe.txt",
    )
    ..addOption(
      'sample',
      help:
          'Initial sampling interval.You should choose a larger initial sampling interval when your address range is bigger.',
      defaultsTo: '10000',
    )
    ..addOption('iter', help: 'Refinement rounds', defaultsTo: '5')
    ..addOption('conc', help: 'tcping concurrency level', defaultsTo: '64')
    ..addOption(
      'timeout',
      help: 'tcping timeout (milliseconds)',
      defaultsTo: '1000',
    )
    ..addOption('port', help: 'Probe port', defaultsTo: '443')
    ..addOption(
      'pingtimes',
      help: 'Number of probe attempts per IP',
      defaultsTo: '4',
    )
    ..addOption(
      'pingtreadhold',
      help: 'Success threshold (0-1)',
      defaultsTo: '0.5',
    )
    ..addOption(
      'radius',
      help: 'Neighborhood radius after success',
      defaultsTo: '100',
    )
    ..addFlag('ipv4', help: 'IPv4 mode (default)');
  final ArgResults argResults;
  try {
    argResults = parser.parse(args);
  } on FormatException catch (e) {
    stdout.writeln(e.message);
    stdout.writeln(parser.usage);
    exit(1);
  }

  final String output = argResults['output'];
  final String? cidr = argResults['cidr'];
  final String? input = argResults['input'];

  final List<String> cidrs = <String>[];
  if (input != null) {
    final File inputFile = File(input);
    if (!inputFile.existsSync()) {
      stdout.writeln('输入文件不存在: $input'.red.bold);
      exit(1);
    }
    final List<String> lines = await inputFile.readAsLines();
    cidrs.addAll(lines.map((e) => e.trim()).where((e) => e.isNotEmpty));
  } else if (cidr != null) {
    cidrs.addAll(
      cidr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty),
    );
  } else {
    stdout.writeln('缺少参数: 需提供 --cidr 或 -i/--input'.bold.red);
    stdout.writeln(parser.usage);
    exit(1);
  }
  if (cidrs.isEmpty) {
    stdout.writeln('没有有效的地址段'.bold.red);
    exit(1);
  }

  for (final c in cidrs) {
    try {
      openCidrRange(c);
    } catch (e) {
      stdout.writeln('地址段不合法: $c ($e)'.red.bold);
      exit(1);
    }
  }

  int parseArg(String name, int fallback) =>
      int.tryParse(argResults[name]) ?? fallback;
  final int sample = parseArg('sample', 10000);
  final int iter = parseArg('iter', 3);
  final int conc = parseArg('conc', 64);
  final int timeoutMs = parseArg('timeout', 1000);
  final int port = parseArg('port', 443);
  final int pingtimes = parseArg('pingtimes', 4);
  final int radius = parseArg('radius', 100);
  final double pingtreadhold =
      double.tryParse(argResults['pingtreadhold']) ?? 0.5;
  final bool ipv4 = argResults['ipv4'];

  final List<String> allResults = <String>[];
  print("cidr ${cidrs.join(",")}".italic.gray);
  print(
    "sample=$sample, iter=$iter, conc=$conc,timeout=${timeoutMs}ms,port=$port,pingtimes=$pingtimes,pingtreadhold=$pingtreadhold,radius=$radius,${ipv4 ? "ipv4" : "ipv6"}\n"
        .italic
        .gray,
  );

  for (final c in cidrs) {
    print("探测地址段: ${c}".bold.green);
    final List<String> result = await refineIpCidrSegment(
      c,
      ipv6: false,
      initialSampleGap: sample,
      iterations: iter,
      radius: radius,
      port: port,
      timeout: Duration(milliseconds: timeoutMs),
      pingTimes: pingtimes,
      pingOkThreadhold: pingtreadhold,
      concurrency: conc,
    );
    allResults.addAll(result);
  }

  final List<String> unique = allResults.toSet().toList();
  await File(output).writeAsString(unique.join('\n'));
  print(
    "探测完成，共 ${cidrs.length.toString().bold.green} 个地址段，"
            "得到 ${unique.length.toString().bold.green} 段(去重)，"
            "已写入 ${output.bold.cyan}"
        .bold,
  );
}
