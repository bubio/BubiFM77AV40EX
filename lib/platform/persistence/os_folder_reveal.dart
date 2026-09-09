import 'dart:io';

import 'package:bubifm77av40ex_platform/bubifm77av40ex_platform.dart';

/// OSのファイルマネージャーでフォルダーを開く（design.md 9）。
///
/// macOSは`bubifm77av40ex_platform`のネイティブチャンネル
/// （[FileManagerReveal]）が担うが、Windows/Linuxはこのパッケージに
/// まだ実装がない（M4〜M6で追加予定）。それまでの間はエクスプローラー/
/// ファイルマネージャーを直接起動する。
class OsFolderReveal {
  const OsFolderReveal({this.macReveal = const FileManagerReveal()});

  final FileManagerReveal macReveal;

  Future<void> reveal(String path) async {
    if (Platform.isWindows) {
      // `explorer.exe`は成功時でも終了コード1を返すことがあるため、
      // 終了コードでは成否を判定しない（win32のExplorer実装の既知の挙動）。
      await Process.start(
        'explorer.exe',
        [path.replaceAll('/', r'\')],
      );
      return;
    }
    await macReveal.reveal(path);
  }
}
