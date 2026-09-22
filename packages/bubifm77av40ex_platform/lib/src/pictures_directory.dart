import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path_provider_windows/path_provider_windows.dart';

/// OSの「ピクチャ」相当のディレクトリ（VID-05）。
///
/// `path_provider`はPictures/Music配下の位置を返すAPIを持たないため、
/// ここで補う。対応していないOSでは[path]が`null`を返し、呼び出し側は
/// 保存ダイアログなどの代替手段へ切り替える。
class PicturesDirectory {
  const PicturesDirectory();

  static const MethodChannel _channel = MethodChannel(
    'bubifm77av40ex/platform',
  );

  /// FOLDERID_Pictures。`WindowsKnownFolder.Pictures`と同じ値だが、解析器が
  /// 条件付きexportのスタブ側（中身が空）を解決するため直接書く。
  static const String _windowsFolderId =
      '{33E28130-4E1E-4676-835A-98395C3BC3BB}';

  /// OSのPicturesディレクトリの絶対パス。未対応のOSでは`null`。
  Future<String?> path() async {
    // MethodChannelはmacOSのみが実装している。WindowsはKnown Folder
    // （SHGetKnownFolderPath）をpath_provider_windows経由で引き、
    // ネイティブプラグインの追加を避ける。
    if (Platform.isWindows) {
      return PathProviderWindows().getPath(_windowsFolderId);
    }
    try {
      return await _channel.invokeMethod<String>('picturesDirectoryPath');
    } on MissingPluginException {
      return null;
    }
  }
}
