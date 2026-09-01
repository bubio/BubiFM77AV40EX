import 'package:bubi_fm77av40ex_core/video_texture.dart';

import 'video_texture_attacher.dart';

/// [VideoTextureAttacher]をFlutterの`MethodChannel`実装へつなぐ。
///
/// このファイルを分けているのは、FFIだけの検証
/// （`tool/native_ffi_check.dart`）が`package:flutter`（`dart:ui`）に
/// 依存できないため。`ffi_emulator_session.dart`はこのファイルを読み込まず、
/// `app`（`lib/app/bootstrap.dart`）だけが組み立てる。
class BubiVideoTextureAttacher implements VideoTextureAttacher {
  const BubiVideoTextureAttacher([this._textures = const BubiVideoTextures()]);

  final BubiVideoTextures _textures;

  @override
  Future<int> attach(int sessionAddress) => _textures.attach(sessionAddress);

  @override
  Future<void> detach(int textureId) => _textures.detach(textureId);
}
