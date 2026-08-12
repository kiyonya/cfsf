
import 'dart:io';
import 'package:prompts/prompts.dart' as prompts;
import 'package:chalkdart/chalkstrings.dart';
import 'config.dart';
import 'libs/hosts.dart';
import 'util/format_print.dart';

Future<void> hostOverride(String fastip,{bool auto = false}) async {
  final Config config = getConfig();
  final String manifestFilePath = config.hostsManifestPath;
  //检查
  final File manifestFile = File(manifestFilePath);
  final Map<String, String> manifest = await readHostsManifest(manifestFile);
  final Map<String, String> systemHosts = await readSystemHosts();
  final List<HostLine> hostLines = [];
  for (var entry in manifest.entries) {
    final host = entry.key;
    final description = entry.value;
    String? formerIp;
    if (systemHosts.containsKey(host)) {
      formerIp = systemHosts[host];
    }
    HostLine line = HostLine(
      host: host,
      ip: fastip,
      description: description,
      formerIp: formerIp,
    );
    hostLines.add(line);
  }
  if (hostLines.isEmpty) {
    print("没有可以加速的网站,请确保清单文件存在且存在未注释的内容".bold.yellow);
    return;
  }
  printHostLines(hostLines);

  final bool overrideHosts = auto ? auto : prompts.getBool(
    "是否将加速策略写入系统hosts文件,这部操作需要管理员权限".bold.aqua,
  );

  if (overrideHosts) {
    try {
      final Map<String, String> modifiedHosts = Map.from(systemHosts);
      for (var line in hostLines) {
        final String host = line.host;
        final String ip = line.ip;
        modifiedHosts[host] = ip;
      }
      final String backup = await writeSystemHosts(modifiedHosts);
      print("hosts文件更改完成,文件备份为: ${backup} ".bold.aqua);
    } catch (e) {
      print("hosts文件写入失败\n Error:${e}".bold.redBright);
    }
  }
}
