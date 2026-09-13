import 'package:flutter/services.dart';

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

  /// OSのMusicディレクトリの絶対パス。未対応のOSでは`null`。
  Future<String?> path() async {
    try {
      return await _channel.invokeMethod<String>('musicDirectoryPath');
    } on MissingPluginException {
      return null;
    }
  }
}
