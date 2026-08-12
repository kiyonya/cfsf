import 'dart:io';

import 'package:chalkdart/chalkstrings.dart';

import 'result.dart';

class HostLine {
  final String host;
  final String ip;
  final String? formerIp;
  final String description;

  HostLine({
    required this.host,
    required this.ip,
    this.formerIp,
    required this.description,
  });
}

final RegExp _ansiPattern = RegExp(r'\x1B\[[0-9;]*m');

int _displayWidth(String text) {
  final String plain = text.replaceAll(_ansiPattern, '');
  int width = 0;
  for (final int rune in plain.runes) {
    width += rune > 0xFF ? 2 : 1;
  }
  return width;
}

String _padRightWidth(String text, int width) {
  final int current = _displayWidth(text);
  if (current >= width) {
    return text;
  }
  return text + ' ' * (width - current);
}

String _padLeftWidth(String text, int width) {
  final int current = _displayWidth(text);
  if (current >= width) {
    return text;
  }
  return ' ' * (width - current) + text;
}

String getQuality(ResultContainer result) {
  final double score = result.score;
  if (score >= 95) {
    return "超好".bold.gold;
  }
  if (score >= 85 && score < 95) {
    return "优秀".bold.green;
  }
  if (score >= 70 && score < 85) {
    return "一般".bold.cyan;
  }
  if (score >= 25 && score < 70) {
    return "较差".bold.yellow;
  }
  return "很差".bold.red;
}

String formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond >= 1e6) {
    return '${(bytesPerSecond / 1e6).toStringAsFixed(1)} MB/s';
  } else if (bytesPerSecond >= 1e3) {
    return '${(bytesPerSecond / 1e3).toStringAsFixed(1)} KB/s';
  } else {
    return '${bytesPerSecond.toStringAsFixed(1)} B/s';
  }
}

void printResults(List<ResultContainer> results) {
  final List<List<String>> rows = [
    ["质量", "IP地址", "丢包率", "延迟", "速度", "地区"],
  ];
  for (final ResultContainer r in results) {
    rows.add([
      getQuality(r),
      r.ip,
      _lossText(r),
      _pingText(r),
      formatSpeed(r.speed ?? 0.0),
      r.colo ?? "N/A",
    ]);
  }
  _printTable(rows, rightAlign: {2, 3, 4});
}

void printHostStatus(Map<String, ResultContainer> results) {
  final List<List<String>> rows = [
    ["状态", "主机", "IP", "延迟", "丢包", "速度", "地区"],
  ];
  final Set<int> errorRows = {};
  for (final MapEntry<String, ResultContainer> e in results.entries) {
    final ResultContainer r = e.value;
    final bool isError = !r.ok;
    if (isError) {
      errorRows.add(rows.length);
    }
    rows.add([
      isError ? "错误" : getQuality(r),
      e.key,
      r.ip,
      _pingText(r),
      _lossText(r),
      formatSpeed(r.speed ?? 0.0),
      r.colo ?? "N/A",
    ]);
  }
  _printTable(rows, rightAlign: {3, 4, 5}, errorRows: errorRows);
}

void printHostLines(List<HostLine> hostLines) {
  final List<List<String>> rows = [
    ["操作", "主机", "描述", "当前地址", "加速地址"],
  ];
  for (final HostLine line in hostLines) {
    final String action = line.formerIp == line.ip
        ? "保持".white.bgCyan
        : (line.formerIp == null
            ? "新增".white.bgGreen
            : "覆盖".white.bgRedBright);
    rows.add([
      action,
      line.host,
      line.description,
      line.formerIp ?? "无加速",
      line.ip,
    ]);
  }
  print("下列网站将会被加速,请仔细确认".bold.aqua);
  print(
    "*hosts加速会修改你原本的hosts文件,下列左侧的操作标记为红色的将会覆盖原有加速\n*hosts文件生效需要时间,如果您正在使用下列网站当中的某个,你可能需要刷新页面\n"
        .yellow,
  );
  _printTable(rows);
  stdout.write("\n\n");
}

void _printTable(
  List<List<String>> rows, {
  Set<int> rightAlign = const {},
  Set<int> errorRows = const {},
  bool leadingBlankLines = true,
}) {
  if (leadingBlankLines) {
    stdout.write("\n\n");
  }
  final List<int> widths = _columnWidths(rows);
  final int total = widths.fold(0, (a, b) => a + b) + (widths.length - 1) * 3;
  print(_formatRow(rows[0], widths, rightAlign: rightAlign, isHeader: true));
  print('─' * total);
  for (int i = 1; i < rows.length; i++) {
    final String formatted = _formatRow(
      rows[i],
      widths,
      rightAlign: rightAlign,
    );
    print(errorRows.contains(i) ? formatted.white.bgRed : formatted);
  }
  if (leadingBlankLines) {
    stdout.write("\n\n");
  }
}

List<int> _columnWidths(List<List<String>> rows) {
  final List<int> widths = List<int>.filled(rows.first.length, 0);
  for (final List<String> row in rows) {
    for (int i = 0; i < row.length; i++) {
      final int w = _displayWidth(row[i]);
      if (w > widths[i]) {
        widths[i] = w;
      }
    }
  }
  return widths;
}

String _formatRow(
  List<String> row,
  List<int> widths, {
  required Set<int> rightAlign,
  bool isHeader = false,
}) {
  final List<String> cells = [];
  for (int i = 0; i < row.length; i++) {
    final String cell = row[i];
    final int width = widths[i];
    final String padded = rightAlign.contains(i)
        ? _padLeftWidth(cell, width)
        : _padRightWidth(cell, width);
    cells.add(isHeader ? padded.bold.white : padded);
  }
  return cells.join("  ");
}

String _pingText(ResultContainer r) {
  return r.ping != null ? '${r.ping!.toStringAsFixed(2)} ms' : "N/A";
}

String _lossText(ResultContainer r) {
  if (r.tcpingAttempt == null || r.tcpingSuccess == null) {
    return "N/A";
  }
  return '${(r.loss * 100).toStringAsFixed(1)}%';
}
