import 'package:flutter/services.dart';

/// コアの画面を Flutter の `Texture` へ渡すための橋渡し。
///
/// 映像だけはネイティブ側（Swift）が描画スレッドから直接コアを読む。
/// `copyPixelBuffer` は raster thread から同期で呼ばれるため、Dart を
/// 経由すると毎フレーム Dart のイベントループを跨ぐことになる
/// （design.md 16.1「映像の受け渡しとmacOS Texture方式」）。
///
/// Dart が扱うのは Texture ID の受け渡しと解除だけである。
class BubiVideoTextures {
  const BubiVideoTextures();

  static const MethodChannel _channel = MethodChannel(
    'bubi_fm77av40ex/core_video',
  );

  /// [sessionAddress] のセッションを Texture として登録し、IDを返す。
  ///
  /// [sessionAddress] は `bfm_session*` のアドレスである。
  Future<int> attach(int sessionAddress) async {
    final id = await _channel.invokeMethod<int>('attach', sessionAddress);
    if (id == null) {
      throw StateError('Textureを登録できませんでした');
    }
    return id;
  }

  /// Texture を解除する。
  ///
  /// **セッションを破棄する前に必ず呼ぶこと。** 逆にすると raster thread が
  /// 解放済みのセッションを読む（design.md 5.1 の終了順序）。
  Future<void> detach(int textureId) {
    return _channel.invokeMethod<void>('detach', textureId);
  }
}
