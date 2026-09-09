import 'dart:io';
import 'dart:typed_data';

import 'package:bubifm77av40ex/platform/audio/wav_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

/// [WavRecorder]（AUD-06）の単体テスト。
///
/// design.md 7.2「初期形式は実出力サンプルレート、2チャネル、16bit
/// little-endian PCMのRIFF/WAVEとする」「終了時は残データを書き、RIFF
/// サイズを確定してからファイルを閉じる」を検証する。
void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('wav_recorder_test');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  test('open→writeChunk→closeでRIFF/WAVEヘッダーが正しく確定する', () async {
    final path = '${tempDir.path}/out.wav';
    final recorder = WavRecorder();
    await recorder.open(path, sampleRate: 48000, channels: 2);

    final chunkA = Uint8List.fromList(List.generate(400, (i) => i % 256));
    final chunkB = Uint8List.fromList(List.generate(200, (i) => (i * 3) % 256));
    await recorder.writeChunk(chunkA);
    await recorder.writeChunk(chunkB);
    await recorder.close();

    final bytes = await File(path).readAsBytes();
    final data = ByteData.sublistView(bytes);

    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(String.fromCharCodes(bytes.sublist(12, 16)), 'fmt ');
    expect(data.getUint32(16, Endian.little), 16); // fmtチャンク長
    expect(data.getUint16(20, Endian.little), 1); // PCM
    expect(data.getUint16(22, Endian.little), 2); // channels
    expect(data.getUint32(24, Endian.little), 48000); // sampleRate
    expect(data.getUint32(28, Endian.little), 48000 * 2 * 2); // byteRate
    expect(data.getUint16(32, Endian.little), 4); // blockAlign
    expect(data.getUint16(34, Endian.little), 16); // bitsPerSample
    expect(String.fromCharCodes(bytes.sublist(36, 40)), 'data');

    final dataBytes = chunkA.length + chunkB.length;
    expect(data.getUint32(40, Endian.little), dataBytes);
    expect(data.getUint32(4, Endian.little), 36 + dataBytes);
    expect(bytes.length, 44 + dataBytes);
    expect(bytes.sublist(44, 44 + chunkA.length), chunkA);
    expect(bytes.sublist(44 + chunkA.length), chunkB);
  });

  test('writeChunkを一度も呼ばずにcloseしても有効な空データのWAVになる', () async {
    final path = '${tempDir.path}/empty.wav';
    final recorder = WavRecorder();
    await recorder.open(path, sampleRate: 44100, channels: 2);
    await recorder.close();

    final bytes = await File(path).readAsBytes();
    final data = ByteData.sublistView(bytes);
    expect(bytes.length, 44);
    expect(data.getUint32(40, Endian.little), 0);
    expect(data.getUint32(4, Endian.little), 36);
  });
}
