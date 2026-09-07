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

  /// マスター音量を変える（0.0〜1.0、design.md 12.4）。
  ///
  /// コアのミキサーには触れず、ホスト最終段のゲインだけを変える
  /// （design.md 16.1「音声はVMの駆動源にしない」の境界を保つため、
  /// `BFM_CMD_SET_VOLUME`はM3のコアミキサー音量調整に残す）。
  void setVolume(double volume);

  /// 再生を止め、資源を解放する。
  Future<void> stop();
}

/// FDD内部機構音（ホスト側合成、AUD-04）の制御境界。
///
/// `AudioSink`とは別軸（`AudioSink.setVolume`はマスター音量）。
/// `FfiEmulatorSession`はこの実体を任意で受け取り、渡されなければ
/// 何もしない（`AudioSink`と同じnull許容パターン）。実装
/// （`FddMechanicalAudioSink`、`lib/platform/audio/`）は`AudioSink`も
/// 実装し、同一インスタンスを両方の役割で`FfiEmulatorSession.create`へ
/// 渡す。
abstract class FddMechanicalSoundSink {
  /// 機構音合成の有効・無効を変える。
  ///
  /// メソッド名は`setFddSoundEnabled`とし、`AudioSink`の
  /// メソッドとは名前を分ける（`FddMechanicalAudioSink`は両方の
  /// interfaceを実装するため、`setVolume(double)`のような同名衝突は
  /// 避ける必要がある）。
  void setFddSoundEnabled(bool enabled);

  /// 機構音の音量を変える（0.0〜1.0）。`AudioSink.setVolume`
  /// （マスター音量）とは別軸。
  void setFddSoundVolume(double volume);

  /// 直近のポーリング区間でアクセスのあったドライブ集合を通知する
  /// （`MediaAccessChanged`と同じ`driveSetFromBits`の結果、
  /// `bits==0`のときは呼ばれない＝実質エッジ的）。
  void notifyDriveAccess(Set<int> accessedDrives);
}
