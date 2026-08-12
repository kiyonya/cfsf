import 'dart:convert';
import 'dart:io';

String getSystemHostsFilePath() {
  if (Platform.isWindows) {
    return r'C:\Windows\System32\drivers\etc\hosts';
  } else {
    return '/etc/hosts';
  }
}

class HostActionItem {
  final String host;
  final String? overrideIp;
  final String? ip;
  final String? description;

  HostActionItem({
    required this.host,
    this.overrideIp,
    this.ip,
    this.description,
  });
}

Future<Map<String, String>> readSystemHosts() async {
  final String hostsFilePath = getSystemHostsFilePath();
  final Map<String, String> hostsMap = {};

  try {
    final File hostsFile = File(hostsFilePath);
    final List<String> lines = await hostsFile.readAsLines();

    for (String line in lines) {
      line = line.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      final List<String> parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 2) {
        final String ip = parts[0];
        final String hostname = parts[1];
        hostsMap[hostname] = ip;
      }
    }
  } catch (e) {
    print('Error reading hosts file: $e');
  }
  return hostsMap;
}

Future<String> writeSystemHosts(Map<String, String> hostsMap) async {
  final String hostsFilePath = getSystemHostsFilePath();
  final File hostsFile = File(hostsFilePath);

  final String backupFilePath = hostsFilePath + '.bak';
  await hostsFile.copy(backupFilePath);
  final List<String> originalLines = await hostsFile.readAsLines();

  final Map<String, String> pending = Map.of(hostsMap); // 待处理的 host -> newIP
  final List<String> newLines = [];
  final lineRegex = RegExp(r'^\s*([^\s]+)\s+(.*?)\s*$');

  for (final line in originalLines) {
    if (line.trim().isEmpty || line.trim().startsWith('#')) {
      newLines.add(line);
      continue;
    }

    final match = lineRegex.firstMatch(line);
    if (match == null) {
      newLines.add(line);
      continue;
    }

    final String ip = match.group(1)!;
    final List<String> hostnames = match.group(2)!.split(RegExp(r'\s+'));
    final List<String> toModify = [];
    final List<String> toKeep = [];

    for (final host in hostnames) {
      if (pending.containsKey(host)) {
        toModify.add(host);
      } else {
        toKeep.add(host);
      }
    }

    if (toModify.isEmpty) {
      newLines.add(line);
    } else {
      if (toKeep.isNotEmpty) {
        newLines.add('$ip\t${toKeep.join(' ')}');
      }
      for (final host in toModify) {
        final newIP = pending[host]!;
        newLines.add('$newIP\t$host');
        pending.remove(host);
      }
    }
  }

  for (final entry in pending.entries) {
    newLines.add('${entry.value}\t${entry.key}');
  }
  final content = newLines.join('\n');
  await hostsFile.writeAsString(content);
  return backupFilePath;
}

Future<Map<String, String>> readHostsManifest(File file) async {
  final Map<String, String> manifest = {};
  if (await file.exists()) {
    final manifestLines = await file.readAsLines(encoding: utf8);
    for (String line in manifestLines) {
      line = line.trim();
      if (line.startsWith("#") || line.isEmpty) {
        continue;
      }
      final sp = line.split(",").map((i) => i.trim()).toList();
      final String? host = sp[0];
      final String description = sp.length > 1 ? sp[1] : "";
      if (host != null) {
        manifest[host] = description;
      }
    }
  }
  return manifest;
}

Future<List<HostActionItem>> readSystemHostsAndHostsManifestToCreateHostsActionList(File manifestFile) async {
  final Map<String, String> manifest = await readHostsManifest(
    manifestFile,
  );
  final Map<String, String> systemHosts = await readSystemHosts();
  final List<HostActionItem> hostItems = [];
  for (var entry in manifest.entries) {
    final host = entry.key;
    final description = entry.value;
    String? ip;
    if (systemHosts.containsKey(host)) {
      ip = systemHosts[host];
    }
    HostActionItem item = HostActionItem(
      host: host,
      description: description,
      ip: ip,
    );
    hostItems.add(item);
  }
  return hostItems;
}