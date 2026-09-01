import 'dart:io';

import 'package:bubi_fm77av40ex/emulator/rom/rom_inventory.dart';
import 'package:bubi_fm77av40ex/emulator/rom/rom_manifest.dart';
import 'package:bubi_fm77av40ex/emulator/rom/rom_requirement.dart';
import 'package:bubi_fm77av40ex/emulator/rom/rom_status.dart';
import 'package:bubi_fm77av40ex/platform/persistence/file_system_rom_scanner.dart';
import 'package:flutter_test/flutter_test.dart';

/// 実ファイルに対する走査の検査。
///
/// 本物のROMは使わない。名前とサイズと可読性だけを見るため、
/// 0埋めのダミーで同じ経路を通せる。
void main() {
  late Directory temp;
  const scanner = FileSystemRomScanner();

  setUp(() {
    temp = Directory.systemTemp.createTempSync('bubi_rom_scan');
  });

  tearDown(() {
    if (temp.existsSync()) {
      temp.deleteSync(recursive: true);
    }
  });

  void writeRom(String name, int size) {
    File('${temp.path}/$name').writeAsBytesSync(List<int>.filled(size, 0));
  }

  Set<String> allRomFileNames() => {
    for (final requirement in fm77av40exRomRequirements)
      ...requirement.fileNames,
  };

  test('APP-06 存在するファイルだけを返す', () async {
    writeRom('INITIATE.ROM', 8 * 1024);

    final probes = await scanner.scan(
      directoryPath: temp.path,
      fileNames: allRomFileNames(),
    );

    expect(probes, hasLength(1));
    expect(probes.single.fileName, 'INITIATE.ROM');
    expect(probes.single.sizeInBytes, 8 * 1024);
    expect(probes.single.readable, isTrue);
    // manifestがなければハッシュは計算しない。
    expect(probes.single.sha256, isNull);
  });

  test('APP-06 ディレクトリがなければ空を返す', () async {
    final probes = await scanner.scan(
      directoryPath: '${temp.path}/does-not-exist',
      fileNames: allRomFileNames(),
    );
    expect(probes, isEmpty);
  });

  test('APP-06 ディレクトリはファイルとして拾わない', () async {
    Directory('${temp.path}/INITIATE.ROM').createSync();
    final probes = await scanner.scan(
      directoryPath: temp.path,
      fileNames: allRomFileNames(),
    );
    expect(probes, isEmpty);
  });

  test('APP-06 大文字小文字の違う実ファイル名でも突き合わせる', () async {
    writeRom('initiate.rom', 8 * 1024);
    final probes = await scanner.scan(
      directoryPath: temp.path,
      fileNames: allRomFileNames(),
    );
    expect(probes, hasLength(1));
    // 実際に存在する綴りをそのまま返す。
    expect(probes.single.fileName, 'initiate.rom');
  });

  test('NFR-07 SHA-256を計算し、manifestと突き合わせられる', () async {
    writeRom('INITIATE.ROM', 8 * 1024);

    final probes = await scanner.scan(
      directoryPath: temp.path,
      fileNames: {'INITIATE.ROM'},
      computeHashes: true,
    );
    final digest = probes.single.sha256;
    expect(digest, isNotNull);
    expect(digest, hasLength(64));

    final matching = RomInventory.evaluate(
      probes: probes,
      manifest: RomManifest.fromEntries([
        RomManifestEntry(
          fileName: 'INITIATE.ROM',
          sizeInBytes: 8 * 1024,
          sha256: digest!,
        ),
      ]),
    );
    expect(matching.entryFor('initiate')!.status, RomStatus.verified);

    final mismatching = RomInventory.evaluate(
      probes: probes,
      manifest: RomManifest.fromEntries([
        RomManifestEntry(
          fileName: 'INITIATE.ROM',
          sizeInBytes: 8 * 1024,
          sha256: 'ff' * 32,
        ),
      ]),
    );
    expect(mismatching.entryFor('initiate')!.status, RomStatus.hashMismatch);
  });

  test('SYS-01 ダミーROM一式から起動可否を判定できる', () async {
    for (final requirement in fm77av40exRomRequirements) {
      writeRom(requirement.primaryFileName, requirement.sizeInBytes);
    }

    final inventory = RomInventory.evaluate(
      probes: await scanner.scan(
        directoryPath: temp.path,
        fileNames: allRomFileNames(),
      ),
    );

    expect(inventory.canBootDos, isTrue);
    expect(inventory.canBootBasic, isTrue);
    expect(inventory.availableFeatures, hasLength(3));
    expect(inventory.bootBlockingProblems, isEmpty);
    expect(inventory.basicBlockingProblems, isEmpty);
    expect(inventory.warnings, isEmpty);
    // manifestを渡していないので、すべて未検証として扱う。
    expect(inventory.hasUnverifiedRoms, isTrue);
  });
}
