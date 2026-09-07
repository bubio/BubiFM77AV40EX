import 'dart:typed_data';

import '../core_ffi/audio_sink.dart';
import 'wav_recorder.dart';

/// [AudioSink]をラップし、最終ミキサー直後のPCMをWAVへ録音する
/// デコレーター（AUD-06）。
///
/// design.md 7.2「音声コールバックはPCMを有界キューへ複製するだけとし、
/// ヘッダー更新とファイルI/Oは`Recorder worker`で直列実行する」に対応する。
/// `pushPcm16`はネイティブのリアルタイム音声コールバックスレッドではなく
/// `FfiEmulatorSession._pullAudio()`のポーリングから呼ばれ、渡される
/// バイト列は毎回新規に確保されたコピーであるため、キューへ参照を積む
/// だけで安全である。別Isolateは導線的な利益が薄いため使わず、単一の
/// futureチェーン（`_chain`）へ`writeChunk`/`close`を追記する形で
/// direct実行し、実際のファイルI/Oが互いに重ならない直列実行を保証する
/// （Dartは単一isolateのため真の並行実行はないが、awaitを跨いだ呼出し順が
/// 入れ替わると同一ファイルハンドルへ複数のI/O要求が同時に飛びうるため、
/// 明示的に直列化する）。キューの長さは「chainに積まれ未完了の書込み数」
/// で数え、上限を超えたら録音を明示的に失敗させる（design.md 7.2）。
///
/// `AudioSink`と[RecordingControl]の両方を実装し、`FfiEmulatorSession`へ
/// 同一インスタンスを`audio`（PCM出力先）と`recording`（録音制御の受け口）
/// の両方として渡す（`lib/app/bootstrap.dart`）。録音点はここより内側
/// （`FddMechanicalAudioSink`）でミックス済みかつ`AudioSink.setVolume`
/// （マスター音量、SoLoud内部で適用）より手前のPCMであり、マスター音量の
/// 影響を受けない。
class RecordingAudioSink implements AudioSink, RecordingControl {
  // 提案どおり`this._maxQueueLength`にすると、privateなフィールド名が
  // そのまま名前付き引数名になり、他ライブラリ（テスト）から
  // `maxQueueLength:`で渡せなくなる。
  RecordingAudioSink(this._inner, {int maxQueueLength = 64})
    // ignore: prefer_initializing_formals
    : _maxQueueLength = maxQueueLength;

  final AudioSink _inner;
  final int _maxQueueLength;

  int _sampleRate = 44100;
  int _channels = 2;

  /// [start]が実際のフォーマットで一度でも呼ばれたか。呼ばれる前は
  /// [_sampleRate]/[_channels]が既定値のままのため、その状態での録音は
  /// 拒否する（AUD-04で一度踏んだ「44100固定」不具合と同じ種類の間違いを
  /// 構造的に防ぐ）。
  bool _formatKnown = false;

  WavRecorder? _recorder;
  int _pendingWrites = 0;
  Future<void> _chain = Future<void>.value();

  @override
  Future<void> start({required int sampleRate, required int channels}) {
    _sampleRate = sampleRate;
    _channels = channels;
    _formatKnown = true;
    return _inner.start(sampleRate: sampleRate, channels: channels);
  }

  @override
  void setVolume(double volume) => _inner.setVolume(volume);

  @override
  Future<void> stop() async {
    await stopRecording();
    await _inner.stop();
  }

  @override
  bool get isRecording => _recorder != null;

  @override
  Future<bool> startRecording(String filePath) async {
    if (isRecording || !_formatKnown) {
      return false;
    }
    final recorder = WavRecorder();
    try {
      await recorder.open(
        filePath,
        sampleRate: _sampleRate,
        channels: _channels,
      );
    } on Object {
      return false;
    }
    _recorder = recorder;
    _pendingWrites = 0;
    _chain = Future<void>.value();
    return true;
  }

  @override
  Future<void> stopRecording() async {
    final recorder = _recorder;
    if (recorder == null) {
      return;
    }
    _recorder = null;
    _chain = _chain.then((_) => recorder.close());
    await _chain;
  }

  @override
  void pushPcm16(Uint8List interleavedLittleEndianPcmBytes) {
    _inner.pushPcm16(interleavedLittleEndianPcmBytes);
    final recorder = _recorder;
    if (recorder == null) {
      return;
    }
    if (_pendingWrites >= _maxQueueLength) {
      // design.md 7.2「キュー飽和時は録音を明示的に失敗させ、音声再生は
      // 継続する」。再生は上ですでに済んでいる。以後のenqueueを止め、
      // 直列chainの末尾でクローズする（進行中の書込みと競合させない）。
      _recorder = null;
      _chain = _chain.then((_) => recorder.close());
      return;
    }
    _pendingWrites++;
    _chain = _chain.then((_) async {
      await recorder.writeChunk(interleavedLittleEndianPcmBytes);
      _pendingWrites--;
    });
  }
}
