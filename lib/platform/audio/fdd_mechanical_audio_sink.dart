import 'dart:typed_data';

import '../core_ffi/audio_sink.dart';
import 'fdd_mechanical_sound.dart';

/// [AudioSink]をラップし、コアPCMへFDD内部機構音（AUD-04）を加算する
/// デコレーター。
///
/// design.md 7.1の図（`FDC状態変化 ─▶ FddMechanicalEvent ─▶ 音声合成voice`
/// `─┐` `コアPCM ─┼▶ limiter ─▶ SoLoud`）のとおり、コアPCMと合成PCMを
/// 加算してからリミッターを通し、ラップ先（`BubiAudioSink`）へ渡す。
///
/// `AudioSink`と[FddMechanicalSoundSink]の両方を実装し、`FfiEmulatorSession`
/// へ同一インスタンスを`audio`（PCM出力先）と`fddMechanicalSound`
/// （機構音の有効・無効／音量／ドライブアクセス通知の受け口）の
/// 両方として渡す（`lib/app/bootstrap.dart`）。
class FddMechanicalAudioSink implements AudioSink, FddMechanicalSoundSink {
  FddMechanicalAudioSink(this._inner, {FddMechanicalSound? synth})
    : _injectedSynth = synth,
      _synth = synth ?? FddMechanicalSound();

  final AudioSink _inner;

  /// テストから明示的に渡された合成器。渡された場合は[start]でも
  /// 作り直さない（テストがsampleRateを制御できるようにするため）。
  final FddMechanicalSound? _injectedSynth;
  FddMechanicalSound _synth;

  bool _enabled = true;
  double _volume = 1.0;
  int _channels = 2;

  @override
  Future<void> start({required int sampleRate, required int channels}) {
    _channels = channels;
    if (_injectedSynth == null) {
      // `bfm_get_audio_format`が返す実際のサンプルレート（既定48kHz、
      // 44100とは限らない）に合わせて作り直す。合わせないとバースト長・
      // トーン周波数・クールダウンがすべて実際の再生速度からずれる。
      _synth = FddMechanicalSound(sampleRate: sampleRate);
    }
    return _inner.start(sampleRate: sampleRate, channels: channels);
  }

  @override
  void setVolume(double volume) => _inner.setVolume(volume);

  @override
  Future<void> stop() => _inner.stop();

  @override
  void setFddSoundEnabled(bool enabled) {
    _enabled = enabled;
  }

  @override
  void setFddSoundVolume(double volume) {
    _volume = volume.clamp(0.0, 1.0);
  }

  /// 「鳴らさない」条件。無効・音量ゼロ・モノラル出力（機構音の左右
  /// 振り分けができない）のいずれか。[notifyDriveAccess]と[pushPcm16]の
  /// 両方で同じ判定を使う。ここでvoiceを積むのを止めておかないと、
  /// 後で条件が外れた瞬間に無関係な古いアクセスぶんのバーストがまとめて
  /// 鳴ってしまう。
  bool get _muted => !_enabled || _volume <= 0.0 || _channels != 2;

  @override
  void notifyDriveAccess(Set<int> accessedDrives) {
    if (_muted || accessedDrives.isEmpty) {
      return;
    }
    _synth.notifyDriveAccess(accessedDrives);
  }

  @override
  void pushPcm16(Uint8List interleavedLittleEndianPcmBytes) {
    if (_muted) {
      _inner.pushPcm16(interleavedLittleEndianPcmBytes);
      return;
    }
    final core = interleavedLittleEndianPcmBytes.buffer.asInt16List(
      interleavedLittleEndianPcmBytes.offsetInBytes,
      interleavedLittleEndianPcmBytes.lengthInBytes ~/ 2,
    );
    final frameCount = core.length ~/ 2;
    final mechanical = _synth.renderInterleavedStereo(frameCount);
    final mixed = Int16List(core.length);
    for (var i = 0; i < core.length; i++) {
      mixed[i] = _softLimit(core[i] + mechanical[i] * _volume);
    }
    _inner.pushPcm16(mixed.buffer.asUint8List());
  }

  /// int16範囲を超える手前から圧縮する簡易ソフトリミッター。
  static int _softLimit(double value) {
    const threshold = 28000.0;
    const ceiling = 32767.0;
    final magnitude = value.abs();
    if (magnitude <= threshold) {
      return value.round();
    }
    final headroom = ceiling - threshold;
    final over = magnitude - threshold;
    // 閾値超過分をtanh的に圧縮し、ceilingへ漸近させる（決してceilingを
    // 超えない）。
    final compressed = threshold + headroom * (over / (over + headroom));
    final limited = value.isNegative ? -compressed : compressed;
    final rounded = limited.round();
    if (rounded > 32767) {
      return 32767;
    }
    if (rounded < -32768) {
      return -32768;
    }
    return rounded;
  }
}
