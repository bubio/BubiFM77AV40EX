import 'package:flutter/services.dart';

/// OSの「ピクチャ」相当のディレクトリ（VID-05）。
///
/// `path_provider`はPictures/Music配下の位置を返すAPIを持たないため、
/// ここで補う。対応していないOSでは[path]が`null`を返し、呼び出し側は
/// 保存ダイアログなどの代替手段へ切り替える。
class PicturesDirectory {
  const PicturesDirectory();

  static const MethodChannel _channel = MethodChannel(
    'bubi_fm77av40ex/platform',
  );

  /// OSのPicturesディレクトリの絶対パス。未対応のOSでは`null`。
  Future<String?> path() async {
    try {
      return await _channel.invokeMethod<String>('picturesDirectoryPath');
    } on MissingPluginException {
      return null;
    }
  }
}
