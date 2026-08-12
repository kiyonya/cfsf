
import 'dart:io';

import 'package:chalkdart/chalkstrings.dart';

void printProgress(int current, int total, int available, {String label = ''}) {
  final percent = (current / total * 100).toStringAsFixed(1);
  final filled = (current / total * 50).round();
  final bar = '='.bold.green * filled + '-'.gray * (50 - filled);
  stdout.write(
    '\r${label.bold.aqua} [$bar] ${percent}% [$current/$total,可用:${available}]'
        .white,
  );
  if(current >= total){
    stdout.write("\n");
  }
}

Future<void> countdown(Duration duration, {String label = '下次检测'}) async {
  final totalSecs = duration.inSeconds;
  if (totalSecs <= 0) return;
  for (int i = totalSecs; i > 0; i--) {
    final percent = (i / totalSecs * 100).toStringAsFixed(0);
    final filled = (i / totalSecs * 50).round();
    final bar = '='.bold.green * filled + '-'.gray * (50 - filled);
    stdout.write('\r${label.bold.aqua} 还剩 ${'$i'.padLeft(3)} 秒 [$bar] $percent%'.white);
    await Future.delayed(const Duration(seconds: 1));
  }
  stdout.write('\n');
}
