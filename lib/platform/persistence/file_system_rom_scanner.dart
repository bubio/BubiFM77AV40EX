import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

import '../../emulator/rom/rom_probe.dart';
import '../../emulator/rom/rom_scanner.dart';

/// ファイルシステムを直接見る [RomScanner]。
///
/// ROM本体をDartヒープへ載せたままにしない。SHA-256はストリームで
/// 読みながら計算し、計算自体は別isolateで行ってUIスレッドを止めない
/// （design.md 10「ハッシュ計算はworkerで行う」）。
class FileSystemRomScanner implements RomScanner {
  const FileSystemRomScanner();

  @override
  Future<List<RomProbe>> scan({
    required String directoryPath,
    required Set<String> fileNames,
    bool computeHashes = false,
  }) async {
    final directory = Directory(directoryPath);
    if (!directory.existsSync()) {
      return const [];
    }

    // 実ファイル名は大文字小文字が揃っているとは限らない。
    // 一覧を1度だけ取り、大文字化して突き合わせる。
    final actualNames = <String, String>{};
    await for (final entity in directory.list(followLinks: true)) {
      if (entity is! File) {
        continue;
      }
      final name = entity.uri.pathSegments.last;
      actualNames[name.toUpperCase()] = name;
    }

    final probes = <RomProbe>[];
    for (final wanted in fileNames) {
      final actual = actualNames[wanted.toUpperCase()];
      if (actual == null) {
        continue;
      }
      probes.add(
        await _probe(
          directoryPath: directoryPath,
          fileName: actual,
          computeHash: computeHashes,
        ),
      );
    }
    return probes;
  }

  Future<RomProbe> _probe({
    required String directoryPath,
    required String fileName,
    required bool computeHash,
  }) async {
    final file = File('$directoryPath${Platform.pathSeparator}$fileName');
    int? size;
    try {
      size = await file.length();
    } on FileSystemException {
      return RomProbe.unreadable(fileName);
    }

    if (!computeHash) {
      // 実際に開けるかを確かめる。長さだけでは権限の異常を見逃す。
      try {
        final handle = await file.open();
        await handle.close();
      } on FileSystemException {
        return RomProbe.unreadable(fileName, sizeInBytes: size);
      }
      return RomProbe(fileName: fileName, sizeInBytes: size, readable: true);
    }

    final String? digest;
    try {
      digest = await Isolate.run(() => _sha256OfFile(file.path));
    } on FileSystemException {
      return RomProbe.unreadable(fileName, sizeInBytes: size);
    }
    if (digest == null) {
      return RomProbe.unreadable(fileName, sizeInBytes: size);
    }
    return RomProbe(
      fileName: fileName,
      sizeInBytes: size,
      readable: true,
      sha256: digest,
    );
  }
}

/// 別isolateで動く。ファイル全体を一度にメモリへ載せない。
Future<String?> _sha256OfFile(String path) async {
  try {
    // package:convert の AccumulatorSink を足さずに済ませる。
    final digests = <Digest>[];
    final output = ChunkedConversionSink<Digest>.withCallback(digests.addAll);
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in File(path).openRead()) {
      input.add(chunk);
    }
    input.close();
    return digests.single.toString();
  } on FileSystemException {
    return null;
  }
}
