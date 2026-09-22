import 'dart:io';

import 'package:bubifm77av40ex_platform/bubifm77av40ex_platform.dart';

/// OSのファイルマネージャーでフォルダーを開く（design.md 9）。
///
/// macOSは`bubifm77av40ex_platform`のネイティブチャンネル
/// （[FileManagerReveal]）が担う。Windows/Linuxはこのパッケージに
/// 実装を持たず、エクスプローラー/ファイルマネージャーを直接起動する。
class OsFolderReveal {
  const OsFolderReveal({this.macReveal = const FileManagerReveal()});

  final FileManagerReveal macReveal;

  Future<void> reveal(String path) async {
    if (Platform.isWindows) {
      // `explorer.exe`は成功時でも終了コード1を返すことがあるため、
      // 終了コードでは成否を判定しない（win32のExplorer実装の既知の挙動）。
      await Process.start('explorer.exe', [path.replaceAll('/', r'\')]);
      return;
    }
    if (Platform.isLinux) {
      // freedesktop.orgの`xdg-open`が、デスクトップ環境の既定の
      // ファイルマネージャー（Nautilus、Dolphin等）へ振り分ける。
      // ファイルマネージャーの終了を待たないよう切り離して起動する。
      try {
        await Process.start('xdg-open', [
          path,
        ], mode: ProcessStartMode.detached);
      } on ProcessException {
        // xdg-utilsのない環境では案内を出せないだけで、機能そのものは
        // 動く（macOSの[FileManagerReveal]が未対応OSで黙るのと同じ扱い）。
      }
      return;
    }
    await macReveal.reveal(path);
  }
}
