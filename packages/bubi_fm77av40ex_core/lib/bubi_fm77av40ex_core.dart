/// 無改変の eFM77AV40EX エミュレーションコアへの FFI 束縛。
///
/// このパッケージが持つのは C ABI の写しだけで、方針も状態も持たない。
/// `EmulatorSession` としての意味づけはアプリ側の `lib/platform/core_ffi/`
/// が与える（design.md 3.1、3.2）。
library;

export 'src/bindings.dart';
export 'src/native_types.dart';
