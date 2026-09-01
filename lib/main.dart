import 'package:flutter/widgets.dart';

import 'app/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // platform実装の組み立てはappの責務（design.md 3.1）。
  runApp(await buildApp());
}
