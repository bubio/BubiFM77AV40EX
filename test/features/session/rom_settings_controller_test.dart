import 'dart:io';

import 'package:bubi_fm77av40ex/emulator/rom/rom_probe.dart';
import 'package:bubi_fm77av40ex/emulator/rom/rom_requirement.dart';
import 'package:bubi_fm77av40ex/emulator/rom/rom_status.dart';
import 'package:bubi_fm77av40ex/emulator/session_state.dart';
import 'package:bubi_fm77av40ex/features/session/rom_settings_controller.dart';
import 'package:bubi_fm77av40ex/features/session/rom_settings_state.dart';
import 'package:bubi_fm77av40ex/features/session/session_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakePreferencesStore preferences;
  late FakeAppDataPaths appDataPaths;
  late FakeRomScanner scanner;
  late List<String> revealed;

  setUp(() {
    preferences = FakePreferencesStore();
    appDataPaths = FakeAppDataPaths();
    scanner = FakeRomScanner();
    revealed = [];
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(
      overrides: [
        romSettingsControllerProvider.overrideWith(
          () => RomSettingsController(
            appDataPaths: appDataPaths,
            preferences: preferences,
            scanner: scanner,
            revealFolder: (path) async => revealed.add(path),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  RomSettingsState readState(ProviderContainer container) =>
      container.read(romSettingsControllerProvider);

  RomSettingsController readController(ProviderContainer container) =>
      container.read(romSettingsControllerProvider.notifier);

  group('APP-06 固定のROMフォルダー', () {
    test('位置を解決して走査まで行う', () async {
      scanner.result = bootRequiredProbes();

      final container = makeContainer();
      await readController(container).restore();

      final state = readState(container);
      expect(state.romsDirectoryPath, '/data/BubiFM77AV40EX/roms');
      expect(scanner.lastDirectoryPath, '/data/BubiFM77AV40EX/roms');
      expect(state.inventory!.canBootDos, isTrue);
    });

    test('走査先は必ず AppDataPaths が返した位置になる', () async {
      appDataPaths.romsPath = '/somewhere/else/roms';
      scanner.result = const [];

      final container = makeContainer();
      await readController(container).restore();

      expect(appDataPaths.romsPathCallCount, 1);
      expect(scanner.lastDirectoryPath, '/somewhere/else/roms');
    });

    test('要求するファイル名はカタログの全候補を含む', () async {
      scanner.result = const [];

      final container = makeContainer();
      await readController(container).restore();

      expect(scanner.lastFileNames, contains('FBASIC302.ROM'));
      expect(scanner.lastFileNames, contains('FBASIC30.ROM'));
      expect(scanner.lastFileNames, contains('KANJI.ROM'));
      expect(
        scanner.lastFileNames!.length,
        fm77av40exRomRequirements.fold<int>(
          0,
          (sum, requirement) => sum + requirement.fileNames.length,
        ),
      );
    });

    test('manifestがなければハッシュを計算しない', () async {
      scanner.result = const [];

      final container = makeContainer();
      await readController(container).restore();

      expect(scanner.lastComputeHashes, isFalse);
    });

    test('フォルダーをOSのファイルマネージャーで開ける', () async {
      scanner.result = bootRequiredProbes();

      final container = makeContainer();
      await readController(container).restore();
      await readController(container).revealRomsDirectory();

      expect(revealed, ['/data/BubiFM77AV40EX/roms']);
    });

    test('位置を解決できなければ失敗として表示する', () async {
      appDataPaths.throwOnRomsPath = const FileSystemException('作成できません');

      final container = makeContainer();
      await readController(container).restore();

      final state = readState(container);
      expect(state.scanFailed, isTrue);
      expect(state.hasDirectory, isFalse);
      expect(state.inventory, isNull);
    });

    test('走査が失敗しても落とさず、失敗として表示する', () async {
      scanner.throwOnScan = const FileSystemException('読み取れません');

      final container = makeContainer();
      await readController(container).restore();

      final state = readState(container);
      expect(state.scanFailed, isTrue);
      expect(state.isScanning, isFalse);
      // 「検証していない」を「検証して正常」と取り違えさせない。
      expect(state.inventory, isNull);
      expect(state.canBootSelectedMode, isFalse);
    });

    test('再走査が成功すれば失敗表示は消える', () async {
      scanner.throwOnScan = const FileSystemException('読み取れません');

      final container = makeContainer();
      await readController(container).restore();
      expect(readState(container).scanFailed, isTrue);

      scanner.throwOnScan = null;
      scanner.result = bootRequiredProbes();
      await readController(container).rescan();

      final state = readState(container);
      expect(state.scanFailed, isFalse);
      expect(state.inventory!.canBootDos, isTrue);
    });

    test('ROMを置き足してから再検証すると結果が変わる', () async {
      scanner.result = bootRequiredProbes();

      final container = makeContainer();
      await readController(container).restore();
      expect(readState(container).inventory!.canBootBasic, isFalse);

      scanner.result = [
        ...bootRequiredProbes(),
        const RomProbe(
          fileName: 'FBASIC302.ROM',
          sizeInBytes: 31 * kib,
          readable: true,
        ),
      ];
      await readController(container).rescan();

      expect(readState(container).inventory!.canBootBasic, isTrue);
    });
  });

  group('SYS-04 ブートモード', () {
    test('既定はBASIC', () {
      final container = makeContainer();
      expect(readState(container).bootMode, BootMode.basic);
    });

    test('変更すると保存され、再起動後も残る', () async {
      final container = makeContainer();
      await readController(container).setBootMode(BootMode.dos);

      expect(readState(container).bootMode, BootMode.dos);
      expect(preferences.getString(RomSettingsController.bootModeKey), 'dos');

      // 別のコンテナ＝再起動相当。同じ保存内容から復元する。
      final restarted = ProviderContainer(
        overrides: [
          romSettingsControllerProvider.overrideWith(
            () => RomSettingsController(
              appDataPaths: appDataPaths,
              preferences: preferences,
              scanner: scanner,
            ),
          ),
        ],
      );
      addTearDown(restarted.dispose);
      expect(
        restarted.read(romSettingsControllerProvider).bootMode,
        BootMode.dos,
      );
    });

    test('DOSは選べてもBASICはF-BASIC次第で起動できない', () async {
      scanner.result = bootRequiredProbes();

      final container = makeContainer();
      await readController(container).restore();

      await readController(container).setBootMode(BootMode.dos);
      expect(readState(container).canBootSelectedMode, isTrue);

      await readController(container).setBootMode(BootMode.basic);
      expect(readState(container).canBootSelectedMode, isFalse);
      expect(
        readState(container).inventory!.entryFor('fbasic')!.status,
        RomStatus.missing,
      );
    });
  });
}
