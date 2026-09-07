import 'dart:math' as math;
import 'dart:typed_data';

/// FDD内部機構音（readWriteのみ、AUD-04）の純Dart合成器。
///
/// `package:flutter`に依存しない（design.md 3.1の`platform/audio/`）。
/// AUD-04着手前の技術検証ゲートで、seek・ヘッドロード／アンロードは
/// コア無改変では観測不能と判明したため（development_plan.md §5.3
/// 「FDDイベント」）、ドライブの読み書きアクセス（readWrite）1種類だけを
/// 対象にする。
///
/// 時間の基準は壁時計ではなく[renderInterleavedStereo]で消費した
/// フレーム数（[_framesRendered]）にする。これにより、同じイベント列と
/// 同じrender呼び出し列を与えれば毎回同一のPCMが得られる（design.md 7.1
/// 「同じイベント列から同じPCMが得られるテスト」）。
class FddMechanicalSound {
  FddMechanicalSound({this.sampleRate = 44100, int seed = 0x9e3779b9})
    : _rngState = seed == 0 ? 1 : seed;

  final int sampleRate;

  /// 同時発音数の上限。超過時は最古のvoiceを破棄する
  /// （design.md 7.1「voice数とイベントキューを有界にし…」）。
  static const int _maxVoices = 4;

  /// 1バーストの長さ。
  static const double _burstSeconds = 0.015;

  /// ドライブごとの最小再発火間隔（連続アクセスのレート制限）。
  static const double _cooldownSeconds = 0.05;

  /// バーストの低域トーン周波数。
  static const double _toneHz = 120;

  /// 内部合成のピーク振幅（int16フルスケールより十分低く抑え、
  /// ミキシング後のリミッターに余裕を残す）。
  static const double _peakAmplitude = 6000;

  final List<_Voice> _voices = [];
  final Map<int, int> _lastTriggerFrame = {};
  int _framesRendered = 0;
  int _rngState;

  /// [accessedDrives]内の各ドライブについて、クールダウンを満たしていれば
  /// 新しいバーストvoiceを1つ発火する。
  void notifyDriveAccess(Set<int> accessedDrives) {
    for (final drive in accessedDrives) {
      _tryTrigger(drive);
    }
  }

  void _tryTrigger(int drive) {
    final cooldownFrames = (sampleRate * _cooldownSeconds).round();
    final last = _lastTriggerFrame[drive];
    if (last != null && _framesRendered - last < cooldownFrames) {
      return;
    }
    _lastTriggerFrame[drive] = _framesRendered;

    final totalFrames = (sampleRate * _burstSeconds).round();
    // ドライブ0は左寄り、それ以外（ドライブ1）は右寄りに弱くパンする。
    final pan = drive == 0
        ? const _Pan(left: 1.0, right: 0.55)
        : const _Pan(left: 0.55, right: 1.0);
    _voices.add(_Voice(totalFrames: totalFrames, pan: pan));
    while (_voices.length > _maxVoices) {
      _voices.removeAt(0);
    }
  }

  /// [frameCount]フレーム分の機構音PCM（インターリーブ・ステレオ、
  /// int16）を合成する。イベントが無ければ全て0を返す。
  Int16List renderInterleavedStereo(int frameCount) {
    final out = Int16List(frameCount * 2);
    for (var i = 0; i < frameCount; i++) {
      var left = 0.0;
      var right = 0.0;
      for (final voice in _voices) {
        if (voice.elapsedFrames >= voice.totalFrames) {
          // このrender呼び出し内で寿命が尽きた（frameCountが1バーストより
          // 長い、design.mdの~15msに対し既定pull間隔20msなど）。
          // 残りのフレームには寄与させない。
          continue;
        }
        final progress = voice.elapsedFrames / voice.totalFrames;
        final envelope = _envelopeAt(progress);
        final tone = math.sin(
          2 * math.pi * _toneHz * voice.elapsedFrames / sampleRate,
        );
        final noise = _nextNoise();
        final sample = envelope * (0.6 * tone + 0.4 * noise) * _peakAmplitude;
        left += sample * voice.pan.left;
        right += sample * voice.pan.right;
        voice.elapsedFrames++;
      }
      out[i * 2] = _clampInt16(left);
      out[i * 2 + 1] = _clampInt16(right);
    }
    _voices.removeWhere((voice) => voice.elapsedFrames >= voice.totalFrames);
    _framesRendered += frameCount;
    return out;
  }

  static double _envelopeAt(double progress) {
    const attack = 0.15;
    if (progress < attack) {
      return progress / attack;
    }
    final decayProgress = (progress - attack) / (1 - attack);
    return math.exp(-4 * decayProgress);
  }

  static int _clampInt16(double value) {
    if (value > 32767) {
      return 32767;
    }
    if (value < -32768) {
      return -32768;
    }
    return value.round();
  }

  double _nextNoise() {
    // xorshift32。決定的で軽量な擬似乱数生成器。
    var x = _rngState;
    x ^= (x << 13) & 0xFFFFFFFF;
    x ^= x >> 17;
    x ^= (x << 5) & 0xFFFFFFFF;
    _rngState = x & 0xFFFFFFFF;
    return (_rngState / 0xFFFFFFFF) * 2 - 1;
  }
}

class _Pan {
  const _Pan({required this.left, required this.right});
  final double left;
  final double right;
}

class _Voice {
  _Voice({required this.totalFrames, required this.pan});
  final int totalFrames;
  final _Pan pan;
  int elapsedFrames = 0;
}
