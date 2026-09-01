/// Textureの登録・解除を行うための境界（design.md 16.1）。
///
/// `package:flutter`（`dart:ui`）に依存させない。`tool/native_ffi_check.dart`
/// がFlutterエンジンなしの`dart run`で`FfiEmulatorSession`を読み込むため、
/// この依存先が`package:flutter`を要求するとコンパイルできなくなる。
/// 実装（`BubiVideoTextureAttacher`）は`app`（`lib/app/bootstrap.dart`）だけが
/// 組み立てる。
abstract class VideoTextureAttacher {
  /// [sessionAddress]（`bfm_session*`のアドレス）のセッションをTextureとして
  /// 登録し、IDを返す。
  Future<int> attach(int sessionAddress);

  /// Textureを解除する。
  Future<void> detach(int textureId);
}
