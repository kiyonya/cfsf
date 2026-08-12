import 'dart:io';

import 'package:chalkdart/chalkstrings.dart';
import 'package:prompts/prompts.dart' as prompts;

import 'src/check.dart';
import 'src/config.dart';
import 'src/hostsfast.dart';
import 'src/ipscan.dart';
import 'src/util/format_print.dart';
import 'src/util/progress.dart';

class Choice {
  final String id;
  final String value;
  Choice({required this.id, required this.value});

  @override
  String toString() {
    return this.value;
  }
}

void main() async {
  final Config config = loadConfig();
  print("CloudFlare FAST=>+>".bold.orange);

  final List<Choice> choices = [
    Choice(id: 'find', value: "寻找IP并优化访问速度".bold.green),
    Choice(id: 'status', value: "检测当前已加速主机的访问质量".bold.cyan),
    Choice(id: 'loop', value: "循环检测自动修复(需要管理员)".bold.orange),
  ];

  while (true) {
    final Choice? c = prompts.choose("选择操作".bold.lightBlue, choices);
    if (c == null) {
      continue;
    }
    if (c.id == 'find') {
      await runFind(config);
    } else if (c.id == 'status') {
      await runStatus(config);
    } else if (c.id == 'loop') {
      await runLoop(config);
    }
  }
}

Future<void> runFind(Config config) async {
  final results = await ipScan(config);
  if (results.isEmpty) {
    print("没有找到可用的IP,请稍后重试".bold.red);
    return;
  }
  printResults(results);
  final best = results.first;
  final bestIp = best.ip;
  final bool askHostOverride = prompts.getBool(
    "是否希望将${bestIp.bold.green}写入hosts文件".bold.aqua,
  );
  if (askHostOverride) {
    await hostOverride(bestIp);
  }
}

Future<void> runStatus(Config config) async {
  final status = await check(config);
  printHostStatus(status);
}

Future<void> runLoop(Config config) async {
  while (true) {
    stdout.write("\n\n");
    print('当前时间: ${DateTime.now().toLocal()}');
    try {
      final status = await check(config);
      printHostStatus(status);
      final int total = status.keys.length;
      final int failed = status.values
          .where((r) => !r.ok || r.score < config.scoreThreshold)
          .length;
      status.clear();
      if (total == 0) {
        print("没有可检测的主机,请检查hosts清单文件".bold.yellow);
      } else if (failed / total > config.failRatio.clamp(0.0, 1.0)) {
        print(
          "失败 ${failed}/${total} 触发修复".bold.yellow,
        );
        final results = await ipScan(config);
        if (results.isEmpty) {
          print("没有找到可用的IP,跳过本次修复".bold.red);
        } else {
          printResults([results.first]);
          final best = results.first;
          final bestIp = best.ip;
          await hostOverride(bestIp, auto: true);
        }
      } else {
        print("今日无事".bold.green);
      }
    } catch (e) {
      print("${e}".red.bold);
    }
    await countdown(
      Duration(seconds: config.loopIntervalSeconds),
      label: "下次检测",
    );
  }
}
