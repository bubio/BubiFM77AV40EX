/// 無改変の eFM77AV40EX エミュレーションコアへの FFI 束縛。
///
/// このパッケージが持つのは C ABI の写しだけで、方針も状態も持たない。
/// `EmulatorSession` としての意味づけはアプリ側の `lib/platform/core_ffi/`
/// が与える（design.md 3.1、3.2）。
///
/// このバレルは`package:flutter`（`dart:ui`）に依存させない。
/// `tool/native_ffi_check.dart`がFlutterエンジンなしの`dart run`で
/// このパッケージを読み込むため、`dart:ui`を要求する時点でコンパイルできなく
/// なる。Textureの橋渡し（`BubiVideoTextures`）は`package:flutter`に依存する
/// ため、別エントリーポイント`video_texture.dart`だけで公開する。
library;

export 'src/bindings.dart';
export 'src/native_types.dart';
