import 'package:bubi_fm77av40ex/emulator/rom/rom_inventory.dart';
import 'package:bubi_fm77av40ex/emulator/session_state.dart';
import 'package:bubi_fm77av40ex/features/session/rom_boot_decision.dart';
import 'package:bubi_fm77av40ex/features/session/rom_settings_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

RomInventory _bootableInventory() =>
    RomInventory.evaluate(probes: bootRequiredProbes());

RomInventory _blockedInventory() {
  final probes = bootRequiredProbes()
    ..removeWhere((probe) => probe.fileName == 'EXTSUB.ROM');
  return RomInventory.evaluate(probes: probes);
}

void main() {
  RomSettingsState state({
    bool hasDirectory = true,
    bool isScanning = false,
    bool scanFailed = false,
    RomInventory? inventory,
  }) {
    return RomSettingsState(
      romsDirectoryPath: hasDirectory ? '/data/roms' : null,
      isScanning: isScanning,
      scanFailed: scanFailed,
      inventory: inventory,
    );
  }

  test('起動中/停止処理中は何もしない', () {
    for (final session in [
      SessionState.starting,
      SessionState.running,
      SessionState.stopping,
      SessionState.failed,
    ]) {
      expect(
        decideRomBootAction(
          emulatorSession: session,
          romSettings: state(inventory: _bootableInventory()),
        ),
        RomBootAction.none,
        reason: '$session',
      );
    }
  });

  test('走査中は何もしない', () {
    expect(
      decideRomBootAction(
        emulatorSession: SessionState.stopped,
        romSettings: state(isScanning: true, inventory: _bootableInventory()),
      ),
      RomBootAction.none,
    );
  });

  test('ROMフォルダー未解決の間は何もしない', () {
    expect(
      decideRomBootAction(
        emulatorSession: SessionState.stopped,
        romSettings: state(hasDirectory: false),
      ),
      RomBootAction.none,
    );
  });

  test('走査前（inventoryなし）は何もしない', () {
    expect(
      decideRomBootAction(
        emulatorSession: SessionState.stopped,
        romSettings: state(),
      ),
      RomBootAction.none,
    );
  });

  test('起動必須6ファイルが揃っていれば自動起動する', () {
    expect(
      decideRomBootAction(
        emulatorSession: SessionState.stopped,
        romSettings: state(inventory: _bootableInventory()),
      ),
      RomBootAction.launch,
    );
  });

  test('起動必須6ファイルに異常があればダイアログを出す', () {
    expect(
      decideRomBootAction(
        emulatorSession: SessionState.stopped,
        romSettings: state(inventory: _blockedInventory()),
      ),
      RomBootAction.showProblem,
    );
  });

  test('走査自体が失敗していればダイアログを出す', () {
    expect(
      decideRomBootAction(
        emulatorSession: SessionState.stopped,
        romSettings: state(scanFailed: true),
      ),
      RomBootAction.showProblem,
    );
  });

  test('F-BASIC ROMが欠けていても起動必須6ファイルが揃っていれば自動起動する', () {
    // F-BASICはbasicRequiredであり、bootRequiredではない。
    // BASICモードを選んでいても、それを理由に止めない
    // （DOSモードで媒体が空でも止めないのと同じ扱い）。
    final inventory = _bootableInventory();
    expect(inventory.canBoot, isTrue);
    expect(inventory.canBootBasic, isFalse);

    expect(
      decideRomBootAction(
        emulatorSession: SessionState.stopped,
        romSettings: state(inventory: inventory),
      ),
      RomBootAction.launch,
    );
  });
}
