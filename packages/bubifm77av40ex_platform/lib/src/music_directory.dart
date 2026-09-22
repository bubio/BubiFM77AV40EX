import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider_windows/path_provider_windows.dart';

/// OSの「ミュージック」相当のディレクトリ（AUD-06）。
///
/// `path_provider`はPictures/Music配下の位置を返すAPIを持たないため、
/// ここで補う。対応していないOSでは[path]が`null`を返し、呼び出し側は
/// 保存ダイアログなどの代替手段へ切り替える。
class MusicDirectory {
  const MusicDirectory();

  static const MethodChannel _channel = MethodChannel(
    'bubifm77av40ex/platform',
  );

  /// FOLDERID_Music。`WindowsKnownFolder.Music`と同じ値だが、解析器が
  /// 条件付きexportのスタブ側（中身が空）を解決するため直接書く。
  static const String _windowsFolderId =
      '{4BD8D571-6D19-48D3-BE97-422220080E43}';

  /// OSのMusicディレクトリの絶対パス。未対応のOSでは`null`。
  Future<String?> path() async {
    // MethodChannelはmacOSのみが実装している。WindowsはKnown Folder
    // （SHGetKnownFolderPath）をpath_provider_windows経由で引き、
    // ネイティブプラグインの追加を避ける。
    if (Platform.isWindows) {
      return PathProviderWindows().getPath(_windowsFolderId);
    }
    try {
      return await _channel.invokeMethod<String>('musicDirectoryPath');
    } on MissingPluginException {
      return null;
    }
  }
}
