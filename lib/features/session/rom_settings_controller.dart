import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../emulator/rom/rom_inventory.dart';
import '../../emulator/rom/rom_manifest.dart';
import '../../emulator/rom/rom_requirement.dart';
import '../../emulator/rom/rom_scanner.dart';
import '../../emulator/session_state.dart';
import '../../platform/persistence/app_data_paths.dart';
import '../../platform/persistence/preferences_store.dart';
import 'rom_settings_state.dart';

/// ROMフォルダーとブートモードを扱うController（SYS-04、APP-03、APP-06）。
///
/// ROMの置き場所は利用者に選ばせず、アプリケーションデータ領域の`roms/`に
/// 固定する（specification.md 6）。物理パスを組み立てず、`AppDataPaths`と
/// `PreferencesStore`というplatform境界だけを使う（design.md 11.2）。
/// ROM本体は読み込まない。
class RomSettingsController extends Notifier<RomSettingsState> {
  RomSettingsController({
    required this.appDataPaths,
    required this.preferences,
    required this.scanner,
    this.manifest,
    this.revealFolder,
  });

  /// `NSUserDefaults`等へ書く鍵。版を跨いで変えない。
  static const String bootModeKey = 'boot.mode';

  final AppDataPaths appDataPaths;
  final PreferencesStore preferences;
  final RomScanner scanner;
  final RomManifest? manifest;

  /// OSのファイルマネージャーでフォルダーを開く手段。未対応なら null。
  final Future<void> Function(String path)? revealFolder;

  @override
  RomSettingsState build() {
    return RomSettingsState(bootMode: _readBootMode());
  }

  BootMode _readBootMode() {
    return switch (preferences.getString(bootModeKey)) {
      'dos' => BootMode.dos,
      _ => BootMode.basic,
    };
  }

  /// ROMフォルダーの位置を解決し、走査まで行う。
  ///
  /// フォルダーがなければ作る。利用者に見つけてもらう必要があるためである。
  Future<void> restore() async {
    String path;
    try {
      path = await appDataPaths.romsDirectoryPath();
    } on Object {
      // 保存領域を用意できない。案内も検証もできないため失敗として出す。
      state = state.copyWith(scanFailed: true, clearInventory: true);
      return;
    }
    state = state.copyWith(romsDirectoryPath: path);
    await rescan();
  }

  /// 現在のフォルダーを走査し、検証結果を更新する。
  Future<void> rescan() async {
    final path = state.romsDirectoryPath;
    if (path == null) {
      return;
    }
    state = state.copyWith(isScanning: true, scanFailed: false);
    try {
      final probes = await scanner.scan(
        directoryPath: path,
        fileNames: {
          for (final requirement in fm77av40exRomRequirements)
            ...requirement.fileNames,
        },
        // manifestがないときはハッシュを計算しない（specification.md 6）。
        computeHashes: manifest != null && !manifest!.isEmpty,
      );
      state = state.copyWith(
        inventory: RomInventory.evaluate(probes: probes, manifest: manifest),
        isScanning: false,
      );
    } on Object {
      // 走査中の異常（フォルダーやアクセス権）で起動経路を落とさない。
      // 検証結果を消し、失敗として表示する。
      state = state.copyWith(
        isScanning: false,
        scanFailed: true,
        clearInventory: true,
      );
    }
  }

  /// ROMフォルダーをOSのファイルマネージャーで開く。
  Future<void> revealRomsDirectory() async {
    final path = state.romsDirectoryPath;
    final reveal = revealFolder;
    if (path == null || reveal == null) {
      return;
    }
    await reveal(path);
  }

  /// ブートモードを変える。反映は次回のリセットまたは再起動から（SYS-04）。
  Future<void> setBootMode(BootMode mode) async {
    if (state.bootMode == mode) {
      return;
    }
    await preferences.setString(bootModeKey, mode.name);
    state = state.copyWith(bootMode: mode);
  }
}
