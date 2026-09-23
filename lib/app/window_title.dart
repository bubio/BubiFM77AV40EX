import 'package:package_info_plus/package_info_plus.dart';
import 'package:window_manager/window_manager.dart';

/// ウィンドウのタイトルバーに出すアプリ名。
const appWindowTitleName = 'BubiFM77AV40EX';

/// タイトルバーの文字列を組み立てる。[buildNumber]が空のときは省く。
String formatWindowTitle({
  required String version,
  required String buildNumber,
}) {
  if (buildNumber.isEmpty) {
    return '$appWindowTitleName $version';
  }
  return '$appWindowTitleName $version ($buildNumber)';
}

/// pubspec.yamlの`version`（ビルド名とビルド番号）をタイトルバーへ表示する。
///
/// デスクトップのみで呼ぶ（`windowManager.ensureInitialized`の後）。
Future<void> applyVersionedWindowTitle() async {
  final info = await PackageInfo.fromPlatform();
  await windowManager.setTitle(
    formatWindowTitle(version: info.version, buildNumber: info.buildNumber),
  );
}
