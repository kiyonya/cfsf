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

final s = 
'''
${"Cloudflare Speed Fix".italic}

用于修复Cloudflare CDN无法访问或者访问速度慢的问题
程序会使用您的网络扫描对于您最快的Cloudflare CDN边缘服务器并通过hosts反代的方式加速访问

- 您的程序目录下的 ${"hosts_manifest.txt".bold.cyan.underline} 存放需要加速的主机名
- 您的程序目录下还应当有ip范围的文件 例如(ipv4.txt / ipv6.txt)
- 默认文件路径,扫描行为,并发数,测速网站以及对服务器地区和状态的限定请修改 ${"config.json".bold.cyan.underline} (这个文件会在第一次运行程序时被创建在程序目录)
- 当您希望覆写hosts或者启动自动修复时,程序必须 ${"以管理员运行".bold.cyan.underline}

Cloudflare Speed Fix - Program by Nekocha(kiyuu)
Github: "https://github.com/kiyonya/cfsf"
Open-source Under ${"  GPL-3.0 License  ".white.bgGray} 
''';


void cliMode(Config config) async {
  print(s.bold.orange);

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
    await hostOverride(config, bestIp);
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
        print("失败 ${failed}/${total} 触发修复".bold.yellow);
        final results = await ipScan(config);
        if (results.isEmpty) {
          print("没有找到可用的IP,跳过本次修复".bold.red);
        } else {
          printResults([results.first]);
          final best = results.first;
          final bestIp = best.ip;
          await hostOverride(config, bestIp, auto: true);
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
