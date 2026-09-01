import '../../emulator/rom/rom_inventory.dart';
import '../../emulator/session_state.dart';

/// ROM設定画面と起動判定が使う状態（design.md 11.1 の`AppSettings`の一部）。
class RomSettingsState {
  const RomSettingsState({
    this.romsDirectoryPath,
    this.bootMode = BootMode.basic,
    this.inventory,
    this.isScanning = false,
    this.scanFailed = false,
  });

  /// 利用者がROMを置くフォルダーのOSパス。
  ///
  /// 位置は固定であり選ばせない（specification.md 6）。案内のために
  /// 画面へ出す。通常ログへは残さない（NFR-07）。
  final String? romsDirectoryPath;

  final BootMode bootMode;

  /// 直近の検証結果。未走査ならnull。
  final RomInventory? inventory;

  final bool isScanning;

  /// 走査そのものが失敗した状態。フォルダーやアクセス権の異常を表す。
  /// 検証結果がないことと、検証して異常だったことを混同させない。
  final bool scanFailed;

  bool get hasDirectory => romsDirectoryPath != null;

  /// 選択中のブートモードで実際に起動できるか。
  bool get canBootSelectedMode => switch (bootMode) {
    BootMode.basic => inventory?.canBootBasic ?? false,
    BootMode.dos => inventory?.canBootDos ?? false,
  };

  RomSettingsState copyWith({
    String? romsDirectoryPath,
    BootMode? bootMode,
    RomInventory? inventory,
    bool? isScanning,
    bool? scanFailed,
    bool clearInventory = false,
  }) {
    return RomSettingsState(
      romsDirectoryPath: romsDirectoryPath ?? this.romsDirectoryPath,
      bootMode: bootMode ?? this.bootMode,
      inventory: clearInventory ? null : (inventory ?? this.inventory),
      isScanning: isScanning ?? this.isScanning,
      scanFailed: scanFailed ?? this.scanFailed,
    );
  }
}
