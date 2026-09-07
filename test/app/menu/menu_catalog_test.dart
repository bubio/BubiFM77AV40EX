import 'package:bubi_fm77av40ex/app/l10n/generated/app_localizations.dart';
import 'package:bubi_fm77av40ex/app/l10n/generated/app_localizations_en.dart';
import 'package:bubi_fm77av40ex/app/menu/menu_catalog.dart';
import 'package:bubi_fm77av40ex/app/menu/menu_command.dart';
import 'package:bubi_fm77av40ex/emulator/session_state.dart';
import 'package:bubi_fm77av40ex/features/display/screen_filter.dart';
import 'package:bubi_fm77av40ex/features/display/screen_fit.dart';
import 'package:bubi_fm77av40ex/features/settings/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Control / Disk / Device / Host`カタログの構造契約（design.md 12.2、12.3）。
///
/// P1/P2はホスト側の実装が揃うまでカタログから外す方針
/// （design.md 12.3を、未実装のP1へも同じ理由で適用）のため、
/// ここではP0項目の分類、順序、種別だけを固定する。
void main() {
  final AppLocalizations l10n = AppLocalizationsEn();

  List<MenuGroup> catalog({
    bool isRunning = true,
    BootMode bootMode = BootMode.basic,
    int speedMultiplier = SpeedMultiplier.x1,
    bool fullSpeed = false,
    CpuType cpuType = CpuType.fast,
    RunOptionSwitches optionSwitches = const RunOptionSwitches(),
    Map<int, String?> fddMedia = const {},
    Map<int, FddDriveSettings> fddDriveSettings = const {},
    Map<int, int> fddBankNum = const {},
    Map<int, int> fddCurBank = const {},
    Map<int, DiskSourceKind> fddSourceKind = const {},
    Map<int, List<FddRecentFile>> fddRecentFiles = const {},
    ScreenFit screenFit = ScreenFit.aspect,
    bool scanlineEnabled = false,
    HostScreenFilter hostFilter = HostScreenFilter.none,
    bool isFullscreen = false,
    bool fullscreenSupported = false,
    bool isRecording = false,
    void Function()? onOpenSoundVolume,
    bool fddMechanicalSoundEnabled = true,
    void Function(bool enabled)? onFddMechanicalSoundEnabledChanged,
    bool isAutoKeying = false,
    void Function()? onStartAutoKey,
    void Function()? onStopAutoKey,
    bool romajiToKana = false,
    void Function(bool enabled)? onRomajiToKanaChanged,
    void Function()? onOpenSaveState,
    void Function()? onOpenLoadState,
    AppLocaleMode localeMode = AppLocaleMode.system,
  }) {
    return buildMenuCatalog(
      l10n: l10n,
      isRunning: isRunning,
      onReset: (_) {},
      bootMode: bootMode,
      onBootModeChanged: (_) {},
      speedMultiplier: speedMultiplier,
      onSpeedMultiplierChanged: (_) {},
      fullSpeed: fullSpeed,
      onFullSpeedChanged: (_) {},
      cpuType: cpuType,
      onCpuTypeChanged: (_) {},
      optionSwitches: optionSwitches,
      onOptionSwitchesChanged: (_) {},
      fddMedia: fddMedia,
      onFddInsert: (_) {},
      onFddEject: (_) {},
      fddDriveSettings: fddDriveSettings,
      onFddWriteProtectChanged: (_, _) {},
      onFddTimingChanged: (_, _) {},
      onFddCrcCheckChanged: (_, _) {},
      onFddInsertBlank: (_, _) {},
      fddBankNum: fddBankNum,
      fddCurBank: fddCurBank,
      onFddBankChanged: (_, _) {},
      fddSourceKind: fddSourceKind,
      onFddSaveAs: (_) {},
      fddRecentFiles: fddRecentFiles,
      onFddInsertFromRecent: (_, _) {},
      onFddClearRecentFiles: (_) {},
      screenFit: screenFit,
      onScreenFitChanged: (_) {},
      scanlineEnabled: scanlineEnabled,
      onScanlineChanged: (_) {},
      hostFilter: hostFilter,
      onHostFilterChanged: (_) {},
      isFullscreen: isFullscreen,
      fullscreenSupported: fullscreenSupported,
      onFullscreenChanged: (_) {},
      onCaptureScreen: () {},
      isRecording: isRecording,
      onStartRecording: () {},
      onStopRecording: () {},
      onOpenSoundVolume: onOpenSoundVolume ?? () {},
      fddMechanicalSoundEnabled: fddMechanicalSoundEnabled,
      onFddMechanicalSoundEnabledChanged:
          onFddMechanicalSoundEnabledChanged ?? (_) {},
      isAutoKeying: isAutoKeying,
      onStartAutoKey: onStartAutoKey ?? () {},
      onStopAutoKey: onStopAutoKey ?? () {},
      romajiToKana: romajiToKana,
      onRomajiToKanaChanged: onRomajiToKanaChanged ?? (_) {},
      onOpenSaveState: onOpenSaveState ?? () {},
      onOpenLoadState: onOpenLoadState ?? () {},
      localeMode: localeMode,
      onLocaleModeChanged: (_) {},
    );
  }

  test('4分類をControl/Disk/Device/Hostの順で持つ', () {
    final groups = catalog();
    expect(groups.map((g) => g.id), [
      MenuGroupId.control,
      MenuGroupId.disk,
      MenuGroupId.device,
      MenuGroupId.host,
    ]);
  });

  test('Control: Reset、Special Reset、区切り、CPU Speed、Full Speed、'
      'CPU Type、Boot Mode、オプションスイッチ3件、区切り、Paste、Stop Paste、'
      'Romaji to Kana、区切り、Save State、Load Stateの順', () {
    final entries = catalog()
        .firstWhere((g) => g.id == MenuGroupId.control)
        .entries;
    expect(entries, hasLength(17));
    expect(
      entries[0],
      isA<MenuAction>().having((e) => e.id, 'id', 'control.reset'),
    );
    expect(
      entries[1],
      isA<MenuAction>().having((e) => e.id, 'id', 'control.specialReset'),
    );
    expect(entries[2], isA<MenuSeparator>());
    final speedGroup = entries[3] as MenuRadioGroup<int>;
    expect(speedGroup.id, 'control.speedMultiplier');
    expect(speedGroup.options.map((o) => o.value), [
      SpeedMultiplier.x1,
      SpeedMultiplier.x2,
      SpeedMultiplier.x4,
      SpeedMultiplier.x8,
      SpeedMultiplier.x16,
    ]);
    expect(
      entries[4],
      isA<MenuCheckbox>().having((e) => e.id, 'id', 'control.fullSpeed'),
    );
    final cpuTypeGroup = entries[5] as MenuRadioGroup<CpuType>;
    expect(cpuTypeGroup.id, 'control.cpuType');
    expect(cpuTypeGroup.options.map((o) => o.value), [
      CpuType.fast,
      CpuType.slow,
    ]);
    final bootModeGroup = entries[6] as MenuRadioGroup<BootMode>;
    expect(bootModeGroup.id, 'control.bootMode');
    expect(bootModeGroup.options.map((o) => o.value), [
      BootMode.basic,
      BootMode.dos,
    ]);
    expect(
      entries[7],
      isA<MenuCheckbox>().having((e) => e.id, 'id', 'control.cycleSteal'),
    );
    expect(
      entries[8],
      isA<MenuCheckbox>().having((e) => e.id, 'id', 'control.extendedRam'),
    );
    expect(
      entries[9],
      isA<MenuCheckbox>().having((e) => e.id, 'id', 'control.syncToHsync'),
    );
    expect(entries[10], isA<MenuSeparator>());
    expect(
      entries[11],
      isA<MenuAction>().having((e) => e.id, 'id', 'control.paste'),
    );
    expect(
      entries[12],
      isA<MenuAction>().having((e) => e.id, 'id', 'control.stopPaste'),
    );
    expect(
      entries[13],
      isA<MenuCheckbox>().having((e) => e.id, 'id', 'control.romajiToKana'),
    );
    expect(entries[14], isA<MenuSeparator>());
    expect(
      entries[15],
      isA<MenuAction>().having((e) => e.id, 'id', 'control.saveState'),
    );
    expect(
      entries[16],
      isA<MenuAction>().having((e) => e.id, 'id', 'control.loadState'),
    );
  });

  test('Control > Paste/Stop Pasteは自動キー入力中かどうかで有効・無効が入れ替わる（INP-03）', () {
    for (final isRunning in [true, false]) {
      for (final isAutoKeying in [true, false]) {
        final entries = catalog(
          isRunning: isRunning,
          isAutoKeying: isAutoKeying,
        ).firstWhere((g) => g.id == MenuGroupId.control).entries;
        final paste = entries[11] as MenuAction;
        final stopPaste = entries[12] as MenuAction;
        expect(paste.enabled, isRunning && !isAutoKeying);
        expect(stopPaste.enabled, isAutoKeying);
      }
    }
  });

  test('Control > Paste/Stop Pasteはonにより開始・停止コールバックを呼ぶ（INP-03）', () {
    var started = false;
    var stopped = false;
    final entries = catalog(
      onStartAutoKey: () => started = true,
      onStopAutoKey: () => stopped = true,
    ).firstWhere((g) => g.id == MenuGroupId.control).entries;
    (entries[11] as MenuAction).onSelected();
    (entries[12] as MenuAction).onSelected();
    expect(started, isTrue);
    expect(stopped, isTrue);
  });

  test(
    'Control > Romaji to Kanaはチェック状態に従いonRomajiToKanaChangedを呼ぶ（INP-03）',
    () {
      bool? changed;
      final entries = catalog(
        romajiToKana: true,
        onRomajiToKanaChanged: (enabled) => changed = enabled,
      ).firstWhere((g) => g.id == MenuGroupId.control).entries;
      final checkbox = entries[13] as MenuCheckbox;
      expect(checkbox.checked, isTrue);
      checkbox.onChanged(false);
      expect(changed, isFalse);
    },
  );

  test('Controlのオプションスイッチのチェック状態は引数に従う', () {
    final entries = catalog(
      optionSwitches: const RunOptionSwitches(
        cycleSteal: true,
        extendedRam: true,
        syncToHsync: true,
      ),
    ).firstWhere((g) => g.id == MenuGroupId.control).entries;
    expect((entries[7] as MenuCheckbox).checked, isTrue);
    expect((entries[8] as MenuCheckbox).checked, isTrue);
    expect((entries[9] as MenuCheckbox).checked, isTrue);
  });

  test('Full Speedのチェック状態は引数に従う', () {
    final entries = catalog(fullSpeed: true)
        .firstWhere((g) => g.id == MenuGroupId.control)
        .entries;
    expect((entries[4] as MenuCheckbox).checked, isTrue);
  });

  test('Controlのリセット項目は停止中に無効化する', () {
    final entries = catalog(isRunning: false)
        .firstWhere((g) => g.id == MenuGroupId.control)
        .entries;
    expect((entries[0] as MenuAction).enabled, isFalse);
    expect((entries[1] as MenuAction).enabled, isFalse);
  });

  test('Disk: FD1、FD2の順でそれぞれInsert/Ejectほかを持つ', () {
    final entries = catalog()
        .firstWhere((g) => g.id == MenuGroupId.disk)
        .entries;
    expect(entries, hasLength(2));
    final fd1 = entries[0] as MenuSubmenu;
    expect(fd1.id, 'disk.fd0');
    expect(fd1.entries.map((e) => e.id), [
      'disk.fd0.insert',
      'disk.fd0.eject',
      'disk.fd0.insertBlank2D',
      'disk.fd0.insertBlank2DD',
      'disk.fd0.writeProtected',
      'disk.fd0.correctTiming',
      'disk.fd0.ignoreCrc',
      'disk.fd0.saveAs',
      'disk.fd0.recent',
    ]);
    final fd2 = entries[1] as MenuSubmenu;
    expect(fd2.id, 'disk.fd1');
  });

  test('Disk: バンクが複数あるD88はバンク選択ラジオを持つ', () {
    final entries = catalog(
      fddBankNum: const {0: 2},
      fddCurBank: const {0: 1},
    ).firstWhere((g) => g.id == MenuGroupId.disk).entries;
    final fd1 = entries[0] as MenuSubmenu;
    final bank = fd1.entries.singleWhere(
      (e) => e.id == 'disk.fd0.bank',
    ) as MenuRadioGroup<int>;
    expect(bank.options.map((o) => o.label), ['Bank 1', 'Bank 2']);
    expect(bank.groupValue, 1);
  });

  test('Disk: 履歴が空ならプレースホルダーを、あれば項目とClearを持つ', () {
    final empty = catalog()
        .firstWhere((g) => g.id == MenuGroupId.disk)
        .entries[0];
    final emptyRecent = (empty as MenuSubmenu).entries.firstWhere(
      (e) => e.id == 'disk.fd0.recent',
    ) as MenuSubmenu;
    expect(emptyRecent.entries.map((e) => e.id), [
      'disk.fd0.recent.empty',
      'disk.fd0.recent.sep',
      'disk.fd0.recent.clear',
    ]);
    expect(
      (emptyRecent.entries[2] as MenuAction).enabled,
      isFalse,
      reason: 'Clear Recent Filesは履歴が空なら無効',
    );

    final withHistory = catalog(
      fddRecentFiles: const {
        0: [(token: 't1', displayName: 'GAME.D88')],
      },
    ).firstWhere((g) => g.id == MenuGroupId.disk).entries[0];
    final recent = (withHistory as MenuSubmenu).entries.firstWhere(
      (e) => e.id == 'disk.fd0.recent',
    ) as MenuSubmenu;
    expect(recent.entries.map((e) => e.id), [
      'disk.fd0.recent.t1',
      'disk.fd0.recent.sep',
      'disk.fd0.recent.clear',
    ]);
    expect((recent.entries[0] as MenuAction).label, 'GAME.D88');
    expect((recent.entries[2] as MenuAction).enabled, isTrue);
  });

  test('Disk: Save Asはconverted/rawのときだけ有効', () {
    final native = catalog(
      fddMedia: const {0: 'GAME.D88'},
      fddSourceKind: const {0: DiskSourceKind.nativeContainer},
    ).firstWhere((g) => g.id == MenuGroupId.disk).entries[0];
    final nativeSaveAs = (native as MenuSubmenu).entries.firstWhere(
      (e) => e.id == 'disk.fd0.saveAs',
    ) as MenuAction;
    expect(nativeSaveAs.enabled, isFalse);

    final converted = catalog(
      fddMedia: const {0: 'GAME.TD0'},
      fddSourceKind: const {0: DiskSourceKind.converted},
    ).firstWhere((g) => g.id == MenuGroupId.disk).entries[0];
    final convertedSaveAs = (converted as MenuSubmenu).entries.firstWhere(
      (e) => e.id == 'disk.fd0.saveAs',
    ) as MenuAction;
    expect(convertedSaveAs.enabled, isTrue);
  });

  test('Disk: Write Protectedは媒体が挿入されているときだけ有効', () {
    final empty = catalog()
        .firstWhere((g) => g.id == MenuGroupId.disk)
        .entries[0];
    final emptyCheckbox = (empty as MenuSubmenu).entries.firstWhere(
      (e) => e.id == 'disk.fd0.writeProtected',
    ) as MenuCheckbox;
    expect(emptyCheckbox.enabled, isFalse);

    final mounted = catalog(fddMedia: const {0: 'GAME.D88'})
        .firstWhere((g) => g.id == MenuGroupId.disk)
        .entries[0];
    final mountedCheckbox = (mounted as MenuSubmenu).entries.firstWhere(
      (e) => e.id == 'disk.fd0.writeProtected',
    ) as MenuCheckbox;
    expect(mountedCheckbox.enabled, isTrue);
  });

  test('Device: Sound、Displayサブメニューを持つ', () {
    final entries = catalog()
        .firstWhere((g) => g.id == MenuGroupId.device)
        .entries;
    expect(entries, hasLength(2));
    final sound = entries[0] as MenuSubmenu;
    expect(sound.id, 'device.sound');
    expect(sound.entries, hasLength(4));
    final radio = sound.entries[0] as MenuRadioGroup<String>;
    expect(radio.options.map((o) => o.label), ['OPN']);
    expect(sound.entries[1], isA<MenuSeparator>());
    final fddMechanismEnabled = sound.entries[2] as MenuCheckbox;
    expect(fddMechanismEnabled.id, 'device.sound.fddMechanismEnabled');
    final volume = sound.entries[3] as MenuAction;
    expect(volume.id, 'device.sound.volume');
    final display = entries[1] as MenuSubmenu;
    expect(display.id, 'device.display');
  });

  test('Device > Sound > VolumeはonOpenSoundVolumeを呼ぶ（AUD-03）', () {
    var called = false;
    final sound =
        catalog(onOpenSoundVolume: () => called = true)
                .firstWhere((g) => g.id == MenuGroupId.device)
                .entries[0]
            as MenuSubmenu;
    final volume = sound.entries[3] as MenuAction;
    expect(volume.enabled, isTrue);
    volume.onSelected();
    expect(called, isTrue);
  });

  test('Device > Sound > FDD Mechanism Soundはチェック状態に従いonFddMechanicalSoundEnabledChangedを呼ぶ（AUD-04）', () {
    bool? changed;
    final sound =
        catalog(
              fddMechanicalSoundEnabled: false,
              onFddMechanicalSoundEnabledChanged: (enabled) =>
                  changed = enabled,
            ).firstWhere((g) => g.id == MenuGroupId.device).entries[0]
            as MenuSubmenu;
    final checkbox = sound.entries[2] as MenuCheckbox;
    expect(checkbox.checked, isFalse);
    checkbox.onChanged(true);
    expect(changed, isTrue);
  });

  test('Device > Displayは走査線チェックボックスを持つ（VID-04）', () {
    final display =
        catalog(scanlineEnabled: true)
                .firstWhere((g) => g.id == MenuGroupId.device)
                .entries[1]
            as MenuSubmenu;
    final scanline = display.entries.single as MenuCheckbox;
    expect(scanline.id, 'device.display.scanline');
    expect(scanline.checked, isTrue);
  });

  test('Host > Capture Screenは起動中だけ有効', () {
    final stopped =
        catalog(isRunning: false)
                .firstWhere((g) => g.id == MenuGroupId.host)
                .entries[2]
            as MenuAction;
    expect(stopped.enabled, isFalse);
    final running =
        catalog(isRunning: true)
                .firstWhere((g) => g.id == MenuGroupId.host)
                .entries[2]
            as MenuAction;
    expect(running.enabled, isTrue);
  });

  test('Host > Rec Sound/Stopは録音中かどうかで有効・無効が入れ替わる', () {
    final stoppedNotRecording = catalog(
      isRunning: false,
      isRecording: false,
    ).firstWhere((g) => g.id == MenuGroupId.host).entries;
    final recSoundWhenStopped = stoppedNotRecording[0] as MenuAction;
    final stopWhenStopped = stoppedNotRecording[1] as MenuAction;
    expect(recSoundWhenStopped.enabled, isFalse);
    expect(stopWhenStopped.enabled, isFalse);

    final runningNotRecording = catalog(
      isRunning: true,
      isRecording: false,
    ).firstWhere((g) => g.id == MenuGroupId.host).entries;
    final recSoundWhenRunning = runningNotRecording[0] as MenuAction;
    final stopWhenRunning = runningNotRecording[1] as MenuAction;
    expect(recSoundWhenRunning.enabled, isTrue);
    expect(stopWhenRunning.enabled, isFalse);

    final runningRecording = catalog(
      isRunning: true,
      isRecording: true,
    ).firstWhere((g) => g.id == MenuGroupId.host).entries;
    final recSoundWhileRecording = runningRecording[0] as MenuAction;
    final stopWhileRecording = runningRecording[1] as MenuAction;
    expect(recSoundWhileRecording.enabled, isFalse);
    expect(stopWhileRecording.enabled, isTrue);
  });

  test('Host: Rec Sound、Stop、Capture Screen、区切り、Screen、区切り、'
      'Languageの順', () {
    final entries = catalog()
        .firstWhere((g) => g.id == MenuGroupId.host)
        .entries;
    expect(entries, hasLength(7));
    expect(
      entries[0],
      isA<MenuAction>().having((e) => e.id, 'id', 'host.recSound'),
    );
    expect(
      entries[1],
      isA<MenuAction>().having((e) => e.id, 'id', 'host.stopRecSound'),
    );
    expect(
      entries[2],
      isA<MenuAction>().having((e) => e.id, 'id', 'host.captureScreen'),
    );
    expect(entries[3], isA<MenuSeparator>());
    expect(
      entries[4],
      isA<MenuSubmenu>().having((e) => e.id, 'id', 'host.screen'),
    );
    expect(entries[5], isA<MenuSeparator>());
    expect(
      entries[6],
      isA<MenuSubmenu>().having((e) => e.id, 'id', 'host.language'),
    );
  });

  test('Host > Screenはfullscreen、fit、filterの順', () {
    final host = catalog().firstWhere((g) => g.id == MenuGroupId.host).entries;
    final screen = host[4] as MenuSubmenu;
    expect(screen.entries, hasLength(3));
    expect(
      screen.entries[0],
      isA<MenuCheckbox>().having((e) => e.id, 'id', 'host.screen.fullscreen'),
    );
    final fit = screen.entries[1] as MenuRadioGroup<ScreenFit>;
    expect(fit.options.map((o) => o.value), [
      ScreenFit.aspect,
      ScreenFit.integer,
      ScreenFit.fill,
    ]);
    final filter = screen.entries[2] as MenuRadioGroup<HostScreenFilter>;
    expect(filter.options.map((o) => o.value), [
      HostScreenFilter.rgb,
      HostScreenFilter.none,
    ]);
  });

  test('Host > Screen > Fullscreenは未対応OSでは無効', () {
    final host = catalog(fullscreenSupported: false)
        .firstWhere((g) => g.id == MenuGroupId.host)
        .entries;
    final screen = host[4] as MenuSubmenu;
    final fullscreen = screen.entries[0] as MenuCheckbox;
    expect(fullscreen.enabled, isFalse);
  });

  test('Host > Languageのラジオはsystem/english/japaneseの順', () {
    final host = catalog().firstWhere((g) => g.id == MenuGroupId.host).entries;
    final language = host[6] as MenuSubmenu;
    final mode = language.entries.single as MenuRadioGroup<AppLocaleMode>;
    expect(mode.options.map((o) => o.value), [
      AppLocaleMode.system,
      AppLocaleMode.english,
      AppLocaleMode.japanese,
    ]);
  });
}
