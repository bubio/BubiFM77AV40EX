import 'dart:typed_data';

/// 音声出力の境界（design.md 7）。
///
/// `package:flutter`（`dart:ui`）に依存させない。`tool/native_ffi_check.dart`
/// がFlutterエンジンなしの`dart run`で`FfiEmulatorSession`を読み込むため、
/// この依存先が`package:flutter`を要求するとコンパイルできなくなる。
/// `dart:typed_data`はFlutterに依存しないDart SDK標準ライブラリであり、
/// この制約に反しない。実装（`BubiAudioSink`）は`app`
/// （`lib/app/bootstrap.dart`）だけが組み立てる。
abstract class AudioSink {
  /// 再生を開始する。[sampleRate]と[channels]は`bfm_get_audio_format`から得る。
  Future<void> start({required int sampleRate, required int channels});

  /// 16bit符号付きリトルエンディアンのPCMを供給する。呼び出し後、
  /// 渡したバッファを呼び手側で書き換えてはならない
  /// （実装側が複製せずそのまま使ってよい）。
  void pushPcm16(Uint8List interleavedLittleEndianPcmBytes);

  /// 再生を止め、資源を解放する。
  Future<void> stop();
}
