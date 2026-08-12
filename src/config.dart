import 'dart:convert';
import 'dart:io';

class Config {
  bool ipv6 = false;
  bool useAvailableCache = true;
  int maxIpCountPreSegments = 128;
  int resultCount = 10;
  int httpHeadCountExpand = 10;
  List<String> coloRequirements = [];
  List<int> allowedStatus = const [200, 201, 301, 302, 307];
  int scoreThreshold = 25;
  double failRatio = 0.2;
  int loopIntervalSeconds = 180;
  double pingOkThreadhold = 0.5;
  int tcpingConcurrency = 32;
  int tcpingPort = 443;
  int tcpingTimes = 4;
  int httpHeadConcurrency = 16;
  int maxBytesRead = 10 * 1024 * 1024;
  Duration tcpingTimeout = const Duration(milliseconds: 1000);
  Duration httpHeadTimeout = const Duration(milliseconds: 1000);
  Duration httpDownloadTimeout = const Duration(milliseconds: 5000);
  Duration downloadTimeout = const Duration(milliseconds: 10000);
  String httpHeadUrl = "https://speedtest.nekocha.top/download";
  String httpDownloadUrl = "https://speed.cloudflare.com/__down?bytes=5242880";
  String availableCacheFilePathV4 = './available_cache_ipv4.txt';
  String availableCacheFilePathV6 = './available_cache_ipv6.txt';
  String resultPath = './result.csv';
  String ipv4File = './ipv4.txt';
  String ipv6File = './ipv6.txt';
  String hostsManifestPath = './hosts_manifest.txt';

  Config();

  static T? _as<T>(Map<String, dynamic> json, String key) {
    final dynamic value = json[key];
    if (value is T) {
      return value;
    }
    return null;
  }

  static List<T> _asList<T>(
    Map<String, dynamic> json,
    String key,
    List<T> fallback,
  ) {
    final dynamic value = json[key];
    if (value is List) {
      return List<T>.from(value.whereType<T>());
    }
    return fallback;
  }

  factory Config.fromJson(Map<String, dynamic> json) {
    final Config config = Config();
    config.ipv6 = _as<bool>(json, 'ipv6') ?? config.ipv6;
    config.useAvailableCache =
        _as<bool>(json, 'useAvailableCache') ?? config.useAvailableCache;
    config.maxIpCountPreSegments =
        _as<int>(json, 'maxIpCountPreSegments') ?? config.maxIpCountPreSegments;
    config.resultCount = _as<int>(json, 'resultCount') ?? config.resultCount;
    config.httpHeadCountExpand =
        _as<int>(json, 'httpHeadCountExpand') ?? config.httpHeadCountExpand;
    config.coloRequirements =
        _asList<String>(json, 'coloRequirements', config.coloRequirements);
    config.allowedStatus =
        _asList<int>(json, 'allowedStatus', config.allowedStatus);
    config.scoreThreshold =
        _as<int>(json, 'scoreThreshold') ?? config.scoreThreshold;
    config.failRatio = _as<double>(json, 'failRatio') ?? config.failRatio;
    config.loopIntervalSeconds =
        _as<int>(json, 'loopIntervalSeconds') ?? config.loopIntervalSeconds;
    config.pingOkThreadhold =
        _as<double>(json, 'pingOkThreadhold') ?? config.pingOkThreadhold;
    config.tcpingConcurrency =
        _as<int>(json, 'tcpingConcurrency') ?? config.tcpingConcurrency;
    config.tcpingPort = _as<int>(json, 'tcpingPort') ?? config.tcpingPort;
    config.tcpingTimes = _as<int>(json, 'tcpingTimes') ?? config.tcpingTimes;
    config.httpHeadConcurrency =
        _as<int>(json, 'httpHeadConcurrency') ?? config.httpHeadConcurrency;
    config.maxBytesRead =
        _as<int>(json, 'maxBytesRead') ?? config.maxBytesRead;
    final int? tcpingTimeoutMs = _as<int>(json, 'tcpingTimeoutMs');
    if (tcpingTimeoutMs != null) {
      config.tcpingTimeout = Duration(milliseconds: tcpingTimeoutMs);
    }
    final int? httpHeadTimeoutMs = _as<int>(json, 'httpHeadTimeoutMs');
    if (httpHeadTimeoutMs != null) {
      config.httpHeadTimeout = Duration(milliseconds: httpHeadTimeoutMs);
    }
    final int? httpDownloadTimeoutMs = _as<int>(json, 'httpDownloadTimeoutMs');
    if (httpDownloadTimeoutMs != null) {
      config.httpDownloadTimeout =
          Duration(milliseconds: httpDownloadTimeoutMs);
    }
    final int? downloadTimeoutMs = _as<int>(json, 'downloadTimeoutMs');
    if (downloadTimeoutMs != null) {
      config.downloadTimeout = Duration(milliseconds: downloadTimeoutMs);
    }    config.httpHeadUrl =
        _as<String>(json, 'httpHeadUrl') ?? config.httpHeadUrl;
    config.httpDownloadUrl =
        _as<String>(json, 'httpDownloadUrl') ?? config.httpDownloadUrl;
    config.availableCacheFilePathV4 =
        _as<String>(json, 'availableCacheFilePathV4') ??
            config.availableCacheFilePathV4;
    config.availableCacheFilePathV6 =
        _as<String>(json, 'availableCacheFilePathV6') ??
            config.availableCacheFilePathV6;
    config.resultPath = _as<String>(json, 'resultPath') ?? config.resultPath;
    config.ipv4File = _as<String>(json, 'ipv4File') ?? config.ipv4File;
    config.ipv6File = _as<String>(json, 'ipv6File') ?? config.ipv6File;
    config.hostsManifestPath =
        _as<String>(json, 'hostsManifestPath') ?? config.hostsManifestPath;
    return config;
  }

  Map<String, dynamic> toJson() {
    return {
      'ipv6': ipv6,
      'useAvailableCache': useAvailableCache,
      'maxIpCountPreSegments': maxIpCountPreSegments,
      'resultCount': resultCount,
      'httpHeadCountExpand': httpHeadCountExpand,
      'coloRequirements': coloRequirements,
      'allowedStatus': allowedStatus,
      'scoreThreshold': scoreThreshold,
      'failRatio': failRatio,
      'loopIntervalSeconds': loopIntervalSeconds,
      'pingOkThreadhold': pingOkThreadhold,
      'tcpingConcurrency': tcpingConcurrency,
      'tcpingPort': tcpingPort,
      'tcpingTimes': tcpingTimes,
      'httpHeadConcurrency': httpHeadConcurrency,
      'maxBytesRead': maxBytesRead,
      'tcpingTimeoutMs': tcpingTimeout.inMilliseconds,
      'httpHeadTimeoutMs': httpHeadTimeout.inMilliseconds,
      'httpDownloadTimeoutMs': httpDownloadTimeout.inMilliseconds,
      'downloadTimeoutMs': downloadTimeout.inMilliseconds,
      'httpHeadUrl': httpHeadUrl,
      'httpDownloadUrl': httpDownloadUrl,
      'availableCacheFilePathV4': availableCacheFilePathV4,
      'availableCacheFilePathV6': availableCacheFilePathV6,
      'resultPath': resultPath,
      'ipv4File': ipv4File,
      'ipv6File': ipv6File,
      'hostsManifestPath': hostsManifestPath,
    };
  }

  static Config load({String path = './config.json'}) {
    final File configFile = File(path);
    Config config = Config();
    if (configFile.existsSync()) {
      try {
        final String configString =
            configFile.readAsStringSync(encoding: utf8);
        final dynamic decoded = jsonDecode(configString);
        if (decoded is Map<String, dynamic>) {
          config = Config.fromJson(decoded);
        }
      } catch (e) {
        config = Config();
      }
    }
    final String prettyJson =
        const JsonEncoder.withIndent('    ').convert(config.toJson());
    configFile.writeAsStringSync(prettyJson, encoding: utf8);
    return config;
  }
}

Config? config;

Config loadConfig({String path = './config.json'}) {
  final Config loaded = Config.load(path: path);
  config = loaded;
  return loaded;
}

Config getConfig() {
  if (config == null) {
    throw Exception("config not initialized before get");
  }
  return config!;
}
