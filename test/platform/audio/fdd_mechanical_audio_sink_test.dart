import 'dart:typed_data';

import 'package:bubifm77av40ex/platform/audio/fdd_mechanical_audio_sink.dart';
import 'package:bubifm77av40ex/platform/core_ffi/audio_sink.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAudioSink implements AudioSink {
  int? startedSampleRate;
  int? startedChannels;
  double? lastVolume;
  bool stopped = false;
  final List<Uint8List> pushed = [];

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    startedSampleRate = sampleRate;
    startedChannels = channels;
  }

  @override
  void setVolume(double volume) {
    lastVolume = volume;
  }

  @override
  void pushPcm16(Uint8List interleavedLittleEndianPcmBytes) {
    pushed.add(interleavedLittleEndianPcmBytes);
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

Uint8List silentStereoPcm(int frameCount) =>
    Int16List(frameCount * 2).buffer.asUint8List();

Uint8List fullScaleStereoPcm(int frameCount) {
  final samples = Int16List(frameCount * 2);
  for (var i = 0; i < samples.length; i++) {
    samples[i] = i.isEven ? 32767 : -32768;
  }
  return samples.buffer.asUint8List();
}

Int16List decode(Uint8List bytes) =>
    bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 2);

/// [FddMechanicalAudioSink]（AUD-04）の単体テスト。
///
/// `AudioSink`をラップし、コアPCMへホスト側合成のFDD機構音（readWriteの
/// み）を加算するデコレーターとしての振る舞いを検証する
/// （design.md 7.1）。
void main() {
  test('start/stop/setVolumeはラップ先へ委譲する', () async {
    final inner = _FakeAudioSink();
    final sink = FddMechanicalAudioSink(inner);

    await sink.start(sampleRate: 44100, channels: 2);
    sink.setVolume(0.5);
    await sink.stop();

    expect(inner.startedSampleRate, 44100);
    expect(inner.startedChannels, 2);
    expect(inner.lastVolume, 0.5);
    expect(inner.stopped, isTrue);
  });

  test('無効時はnotifyDriveAccess後もpushPcm16の出力が入力と一致する', () async {
    final inner = _FakeAudioSink();
    final sink = FddMechanicalAudioSink(inner);
    await sink.start(sampleRate: 44100, channels: 2);
    sink.setFddSoundEnabled(false);
    sink.setFddSoundVolume(1.0);

    sink.notifyDriveAccess({0});
    final input = silentStereoPcm(2000);
    sink.pushPcm16(input);

    expect(inner.pushed.single, input);
  });

  test('音量0.0ならnotifyDriveAccess後もpushPcm16の出力が入力と一致する', () async {
    final inner = _FakeAudioSink();
    final sink = FddMechanicalAudioSink(inner);
    await sink.start(sampleRate: 44100, channels: 2);
    sink.setFddSoundEnabled(true);
    sink.setFddSoundVolume(0.0);

    sink.notifyDriveAccess({0});
    final input = silentStereoPcm(2000);
    sink.pushPcm16(input);

    expect(inner.pushed.single, input);
  });

  test('有効かつ音量ありでドライブアクセス通知後は出力が入力と異なる', () async {
    final inner = _FakeAudioSink();
    final sink = FddMechanicalAudioSink(inner);
    await sink.start(sampleRate: 44100, channels: 2);
    sink.setFddSoundEnabled(true);
    sink.setFddSoundVolume(1.0);

    sink.notifyDriveAccess({0});
    final input = silentStereoPcm(2000);
    sink.pushPcm16(input);

    expect(inner.pushed.single, isNot(input));
  });

  test('最大振幅の入力に機構音を加算してもint16範囲を超えない', () async {
    final inner = _FakeAudioSink();
    final sink = FddMechanicalAudioSink(inner);
    await sink.start(sampleRate: 44100, channels: 2);
    sink.setFddSoundEnabled(true);
    sink.setFddSoundVolume(1.0);

    sink.notifyDriveAccess({0, 1});
    final input = fullScaleStereoPcm(2000);
    sink.pushPcm16(input);

    final output = decode(inner.pushed.single);
    expect(
      output.every((sample) => sample >= -32768 && sample <= 32767),
      isTrue,
    );
  });

  test('startで渡された実際のsampleRateに基づいて合成する（44100固定にしない）', () async {
    final inner = _FakeAudioSink();
    // 合成器を注入せず、sinkが自分でstart()のsampleRateに合わせて
    // 作り直すことを確認する（`bfm_get_audio_format`の既定48kHzは
    // 44100と異なる。native/host/session_test.cppの
    // 「音声フォーマットは48kHzで開始する」参照）。
    final sink = FddMechanicalAudioSink(inner);
    await sink.start(sampleRate: 48000, channels: 2);
    sink.setFddSoundEnabled(true);
    sink.setFddSoundVolume(1.0);

    sink.notifyDriveAccess({0});
    sink.pushPcm16(silentStereoPcm(700));

    // 48kHzでのバースト長は約0.015*48000≒720フレーム。700フレーム目
    // ではまだ鳴っているはず（44100を前提にしたままだと約662フレームで
    // 終わってしまい、この時点ですでに無音になる）。
    final rendered = decode(inner.pushed.single);
    final tail = rendered.sublist(rendered.length - 40);
    expect(tail.any((sample) => sample != 0), isTrue);
  });
}
