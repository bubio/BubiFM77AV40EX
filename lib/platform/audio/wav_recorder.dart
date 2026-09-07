import 'dart:io';
import 'dart:typed_data';

/// RIFF/WAVEへ16bit PCMをストリーミング書込みする低レベルの書き手。
///
/// design.md 7.2「初期形式は実出力サンプルレート、2チャネル、16bit
/// little-endian PCMのRIFF/WAVEとする」「終了時は残データを書き、RIFF
/// サイズを確定してからファイルを閉じる」に対応する。`AppDataLocation`の
/// `writeAtomic`は一括書込み専用で使えないため、`dart:io`の
/// `RandomAccessFile`を直接使う（`os_app_data_paths.dart`と同じく
/// platform層の責務内）。
class WavRecorder {
  RandomAccessFile? _file;
  int _dataBytesWritten = 0;

  static const int _headerBytes = 44;

  bool get isOpen => _file != null;

  /// [path]をプレースホルダーヘッダー付きで開く。
  Future<void> open(
    String path, {
    required int sampleRate,
    required int channels,
  }) async {
    final file = await File(path).open(mode: FileMode.write);
    _dataBytesWritten = 0;
    await file.writeFrom(
      _buildHeader(sampleRate: sampleRate, channels: channels, dataBytes: 0),
    );
    _file = file;
  }

  /// PCMバイト列を追記する。
  Future<void> writeChunk(Uint8List bytes) async {
    final file = _file;
    if (file == null || bytes.isEmpty) {
      return;
    }
    await file.writeFrom(bytes);
    _dataBytesWritten += bytes.length;
  }

  /// ヘッダーのサイズを確定し、ファイルを閉じる。
  Future<void> close() async {
    final file = _file;
    if (file == null) {
      return;
    }
    _file = null;
    await file.setPosition(4);
    await file.writeFrom(_uint32Le(36 + _dataBytesWritten));
    await file.setPosition(40);
    await file.writeFrom(_uint32Le(_dataBytesWritten));
    await file.flush();
    await file.close();
  }

  static Uint8List _buildHeader({
    required int sampleRate,
    required int channels,
    required int dataBytes,
  }) {
    const bitsPerSample = 16;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final byteRate = sampleRate * blockAlign;
    final header = BytesBuilder();
    header.add('RIFF'.codeUnits);
    header.add(_uint32Le(36 + dataBytes));
    header.add('WAVE'.codeUnits);
    header.add('fmt '.codeUnits);
    header.add(_uint32Le(16));
    header.add(_uint16Le(1)); // PCM
    header.add(_uint16Le(channels));
    header.add(_uint32Le(sampleRate));
    header.add(_uint32Le(byteRate));
    header.add(_uint16Le(blockAlign));
    header.add(_uint16Le(bitsPerSample));
    header.add('data'.codeUnits);
    header.add(_uint32Le(dataBytes));
    final bytes = header.toBytes();
    assert(bytes.length == _headerBytes);
    return bytes;
  }

  static Uint8List _uint32Le(int value) {
    final bytes = ByteData(4)..setUint32(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static Uint8List _uint16Le(int value) {
    final bytes = ByteData(2)..setUint16(0, value, Endian.little);
    return bytes.buffer.asUint8List();
  }
}
