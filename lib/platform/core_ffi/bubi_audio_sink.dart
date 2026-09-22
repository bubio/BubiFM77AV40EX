import 'dart:typed_data';

import 'package:flutter_soloud/flutter_soloud.dart';

import 'audio_sink.dart';

/// [AudioSink]をSoLoudのバッファストリームへつなぐ。
///
/// このファイルを分けているのは、FFIだけの検証
/// （`tool/native_ffi_check.dart`）が`package:flutter`（`dart:ui`）に
/// 依存できないため。`ffi_emulator_session.dart`はこのファイルを読み込まず、
/// `app`（`lib/app/bootstrap.dart`）だけが組み立てる。
///
/// upstreamの「音声クロック駆動」は採らない（design.md 16.1）。ここは
/// `FfiEmulatorSession`が`bfm_read_audio`で引き出したPCMを供給するだけで、
/// 音声側からVMを進めることはない。
class BubiAudioSink implements AudioSink {
  BubiAudioSink([SoLoud? soloud]) : _soloud = soloud ?? SoLoud.instance;

  final SoLoud _soloud;
  AudioSource? _source;
  double _pendingVolume = 1.0;

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    final channelsEnum = channels == 1 ? Channels.mono : Channels.stereo;
    if (!_soloud.isInitialized) {
      await _soloud.init(sampleRate: sampleRate, channels: channelsEnum);
    }
    // 生存中ずっと続く無音混じりのライブ入力であり、シークバックはしない
    // ため、再生済みデータを溜めずに解放する BufferingType.released を使う。
    //
    // bufferingTimeNeedsは再生開始（とアンダーラン後の再開）までに溜める量で、
    // そのまま定常の音声遅延になる。供給は20ms周期（FfiEmulatorSessionの
    // _audioPullInterval）で一定量ずつ届くため、その2周期分あれば途切れない。
    // 0.1秒では、コア側の50ms単位の生成遅延と合わせて映像より音が約150〜200ms
    // 遅れ、曲に同期した演出（イースのOP等）で画像の先行が目に見えていた。
    final source = _soloud.setBufferStream(
      maxBufferSizeDuration: const Duration(seconds: 2),
      bufferingType: BufferingType.released,
      bufferingTimeNeeds: 0.02,
      sampleRate: sampleRate,
      channels: channelsEnum,
      format: BufferType.s16le,
    );
    _source = source;
    _soloud.play(source);
    _soloud.setGlobalVolume(_pendingVolume);
  }

  @override
  void setVolume(double volume) {
    _pendingVolume = volume;
    if (_soloud.isInitialized) {
      _soloud.setGlobalVolume(volume);
    }
  }

  @override
  void pushPcm16(Uint8List interleavedLittleEndianPcmBytes) {
    final source = _source;
    if (source == null) {
      return;
    }
    _soloud.addAudioDataStream(source, interleavedLittleEndianPcmBytes);
  }

  @override
  Future<void> stop() async {
    final source = _source;
    _source = null;
    if (source == null) {
      return;
    }
    _soloud.setDataIsEnded(source);
    await _soloud.disposeSource(source);
  }
}
