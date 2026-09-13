import 'dart:io';
import 'dart:typed_data';

import 'package:bubifm77av40ex/platform/audio/recording_audio_sink.dart';
import 'package:bubifm77av40ex/platform/core_ffi/audio_sink.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAudioSink implements AudioSink {
  final List<Uint8List> pushed = [];
  bool stopped = false;

  @override
  Future<void> start({required int sampleRate, required int channels}) async {}

  @override
  void setVolume(double volume) {}

  @override
  void pushPcm16(Uint8List interleavedLittleEndianPcmBytes) {
    pushed.add(interleavedLittleEndianPcmBytes);
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

Uint8List pcmOf(int byteLength, {int seed = 0}) =>
    Uint8List.fromList(List.generate(byteLength, (i) => (i + seed) % 256));

/// [RecordingAudioSink]（AUD-06）の単体テスト。
///
/// design.md 7.2の「音声再生は録音の成否に関わらず継続する」
/// 「キュー飽和時は録音を明示的に失敗させる」を検証する。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'recording_audio_sink_test',
    );
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('startより前にstartRecordingを呼ぶとfalseが返る（44100固定にしない）', () async {
    final inner = _FakeAudioSink();
    final sink = RecordingAudioSink(inner);
    // start()を一度も呼ばないまま録音を試みる。実際のsampleRateが
    // 判明していないため、既定値のまま書き出してしまう不具合
    // （AUD-04で一度踏んだ「44100固定」と同種）を構造的に防ぐ。
    final path = '${tempDir.path}/out.wav';

    final started = await sink.startRecording(path);

    expect(started, isFalse);
    expect(await File(path).exists(), isFalse);
  });

  test('pushPcm16は録音の有無に関わらず常にラップ先へ届く', () async {
    final inner = _FakeAudioSink();
    final sink = RecordingAudioSink(inner);
    await sink.start(sampleRate: 44100, channels: 2);

    final bytes = pcmOf(400);
    sink.pushPcm16(bytes);

    expect(inner.pushed.single, bytes);
    expect(sink.isRecording, isFalse);
  });

  test('録音中はpushPcm16されたPCMがファイルへ書かれる', () async {
    final inner = _FakeAudioSink();
    final sink = RecordingAudioSink(inner);
    await sink.start(sampleRate: 44100, channels: 2);

    final path = '${tempDir.path}/out.wav';
    final started = await sink.startRecording(path);
    expect(started, isTrue);
    expect(sink.isRecording, isTrue);

    final chunkA = pcmOf(400, seed: 1);
    final chunkB = pcmOf(200, seed: 2);
    sink.pushPcm16(chunkA);
    sink.pushPcm16(chunkB);
    await sink.stopRecording();

    expect(sink.isRecording, isFalse);
    final bytes = await File(path).readAsBytes();
    expect(bytes.length, 44 + chunkA.length + chunkB.length);
    expect(bytes.sublist(44, 44 + chunkA.length), chunkA);
    expect(bytes.sublist(44 + chunkA.length), chunkB);
  });

  test('既に録音中にstartRecordingを呼ぶとfalseが返り既存の録音は続く', () async {
    final inner = _FakeAudioSink();
    final sink = RecordingAudioSink(inner);
    await sink.start(sampleRate: 44100, channels: 2);

    final firstPath = '${tempDir.path}/first.wav';
    final secondPath = '${tempDir.path}/second.wav';
    expect(await sink.startRecording(firstPath), isTrue);
    expect(await sink.startRecording(secondPath), isFalse);
    expect(await File(secondPath).exists(), isFalse);

    final chunk = pcmOf(100);
    sink.pushPcm16(chunk);
    await sink.stopRecording();

    final bytes = await File(firstPath).readAsBytes();
    expect(bytes.length, 44 + chunk.length);
  });

  test('キュー上限を超えると録音は明示的に停止し、音声再生は継続する', () async {
    final inner = _FakeAudioSink();
    final sink = RecordingAudioSink(inner, maxQueueLength: 2);
    await sink.start(sampleRate: 44100, channels: 2);

    final path = '${tempDir.path}/out.wav';
    await sink.startRecording(path);

    // ドレイン（await recorder.writeChunk）が進む前に立て続けに積み、
    // in-flight/未完了カウントが上限を超えるようにする。
    for (var i = 0; i < 10; i++) {
      sink.pushPcm16(pcmOf(4, seed: i));
    }

    expect(inner.pushed, hasLength(10)); // 再生は録音の成否に関係なく継続
    expect(sink.isRecording, isFalse);
  });

  test('drainが進んだ後は未完了カウントが減り、上限に達しない', () async {
    final inner = _FakeAudioSink();
    final sink = RecordingAudioSink(inner, maxQueueLength: 2);
    await sink.start(sampleRate: 44100, channels: 2);

    final path = '${tempDir.path}/out.wav';
    await sink.startRecording(path);

    sink.pushPcm16(pcmOf(4, seed: 1));
    // マイクロタスクを一巡させ、直列chainが書込みを終えて
    // `_pendingWrites`を減らす機会を与える。減らないバグがあれば、
    // 以降のpushで即座に飽和してしまう。
    await Future<void>.delayed(Duration.zero);
    sink.pushPcm16(pcmOf(4, seed: 2));
    await Future<void>.delayed(Duration.zero);

    expect(sink.isRecording, isTrue);
    await sink.stopRecording();
  });

  test('stop()を録音中に呼ぶとファイルがファイナライズされる', () async {
    final inner = _FakeAudioSink();
    final sink = RecordingAudioSink(inner);
    await sink.start(sampleRate: 44100, channels: 2);

    final path = '${tempDir.path}/out.wav';
    await sink.startRecording(path);
    final chunk = pcmOf(100);
    sink.pushPcm16(chunk);
    await sink.stop();

    expect(inner.stopped, isTrue);
    expect(sink.isRecording, isFalse);
    final bytes = await File(path).readAsBytes();
    expect(bytes.length, 44 + chunk.length);
  });
}
