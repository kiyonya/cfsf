import 'cli.dart';
import 'src/config.dart';

void main() async {
  final Config config = loadConfig();
  cliMode(config);
}


