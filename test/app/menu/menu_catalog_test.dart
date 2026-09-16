import 'package:bubifm77av40ex/app/l10n/generated/app_localizations.dart';
import 'package:bubifm77av40ex/app/l10n/generated/app_localizations_en.dart';
import 'package:bubifm77av40ex/app/menu/menu_catalog.dart';
import 'package:bubifm77av40ex/app/menu/menu_command.dart';
import 'package:bubifm77av40ex/emulator/session_state.dart';
import 'package:bubifm77av40ex/features/display/screen_filter.dart';
import 'package:bubifm77av40ex/features/display/screen_fit.dart';
import 'package:bubifm77av40ex/features/settings/settings_state.dart';
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
    bool cmtInserted = false,
    bool cmtPlaying = false,
    bool cmtRecording = false,
    void Function()? onCmtPlay,
    void Function()? onCmtRec,
    void Function()? onCmtEject,
    void Function()? onCmtPlayButton,
    void Function()? onCmtStopButton,
    void Function()? onCmtFastForward,
    void Function()? onCmtFastRewind,
    CmtDriveSettings cmtDriveSettings = const CmtDriveSettings(),
    void Function(bool enabled)? onCmtWaveShapingChanged,
    List<CmtRecentFile> cmtRecentFiles = const [],
    void Function(String token)? onCmtPlayFromRecent,
    void Function()? onCmtClearRecentFiles,
    CmtSoundSettings cmtSoundSettings = const CmtSoundSettings(),
    void Function(CmtSoundKind kind, bool enabled)? onCmtSoundEnabledChanged,
    void Function()? onOpenCmtSoundVolume,
    ScreenFit screenFit = ScreenFit.aspect,
    bool scanlineEnabled = false,
    HostScreenFilter hostFilter = HostScreenFilter.none,
    bool windowScaleSupported = false,
    List<int> windowScaleMultipliers = const [],
    int? windowScaleCurrentMultiplier,
    void Function(int multiplier)? onWindowScaleChanged,
    bool isFullscreen = false,
    bool fullscreenSupported = false,
    bool isRecording = false,
    void Function()? onOpenSoundVolume,
    void Function()? onOpenJoystickAssignment,
    bool fddMechanicalSoundEnabled = true,
    void Function(bool enabled)? onFddMechanicalSoundEnabledChanged,
    bool isAutoKeying = false,
    void Function()? onStartAutoKey,
    void Function()? onStopAutoKey,
    bool romajiToKana = false,
    void Function(bool enabled)? onRomajiToKanaChanged,
    void Function()? onOpenSaveState,
    void Function()? onOpenLoadState,
    bool showStatusBar = true,
    void Function(bool visible)? onShowStatusBarChanged,
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
      cmtInserted: cmtInserted,
      cmtPlaying: cmtPlaying,
      cmtRecording: cmtRecording,
      onCmtPlay: onCmtPlay ?? () {},
      onCmtRec: onCmtRec ?? () {},
      onCmtEject: onCmtEject ?? () {},
      onCmtPlayButton: onCmtPlayButton ?? () {},
      onCmtStopButton: onCmtStopButton ?? () {},
      onCmtFastForward: onCmtFastForward ?? () {},
      onCmtFastRewind: onCmtFastRewind ?? () {},
      cmtDriveSettings: cmtDriveSettings,
      onCmtWaveShapingChanged: onCmtWaveShapingChanged ?? (_) {},
      cmtRecentFiles: cmtRecentFiles,
      onCmtPlayFromRecent: onCmtPlayFromRecent ?? (_) {},
      onCmtClearRecentFiles: onCmtClearRecentFiles ?? () {},
      cmtSoundSettings: cmtSoundSettings,
      onCmtSoundEnabledChanged: onCmtSoundEnabledChanged ?? (_, _) {},
      onOpenCmtSoundVolume: onOpenCmtSoundVolume ?? () {},
      screenFit: screenFit,
      onScreenFitChanged: (_) {},
      scanlineEnabled: scanlineEnabled,
      onScanlineChanged: (_) {},
      hostFilter: hostFilter,
      onHostFilterChanged: (_) {},
      windowScaleSupported: windowScaleSupported,
      windowScaleMultipliers: windowScaleMultipliers,
      windowScaleCurrentMultiplier: windowScaleCurrentMultiplier,
      onWindowScaleChanged: onWindowScaleChanged ?? (_) {},
      isFullscreen: isFullscreen,
      fullscreenSupported: fullscreenSupported,
      onFullscreenChanged: (_) {},
      onCaptureScreen: () {},
      isRecording: isRecording,
      onStartRecording: () {},
      onStopRecording: () {},
      onOpenSoundVolume: onOpenSoundVolume ?? () {},
      onOpenJoystickAssignment: onOpenJoystickAssignment ?? () {},
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
      showStatusBar: showStatusBar,
      onShowStatusBarChanged: onShowStatusBarChanged ?? (_) {},
      localeMode: localeMode,
      onLocaleModeChanged: (_) {},
    );
  }

  test('5分類をControl/Disk/CMT/Device/Hostの順で持つ', () {
    final groups = catalog();
    expect(groups.map((g) => g.id), [
      MenuGroupId.control,
      MenuGroupId.disk,
      MenuGroupId.cmt,
      MenuGroupId.device,
      MenuGroupId.host,
    ]);
  });

  test('Control: Reset、Special Reset、区切り、CPU Speed、Full Speed、'
      '区切り、Paste、Stop Paste、Romaji to Kana、区切り、'
      'Save State、Load Stateの順', () {
    final entries = catalog()
        .firstWhere((g) => g.id == MenuGroupId.control)
        .entries;
    expect(entries, hasLength(12));
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
    expect(entries[5], isA<MenuSeparator>());
    expect(
      entries[6],
      isA<MenuAction>().having((e) => e.id, 'id', 'control.paste'),
    );
    expect(
      entries[7],
      isA<MenuAction>().having((e) => e.id, 'id', 'control.stopPaste'),
    );
    expect(
      entries[8],
      isA<MenuCheckbox>().having((e) => e.id, 'id', 'control.romajiToKana'),
    );
    expect(entries[9], isA<MenuSeparator>());
    expect(
      entries[10],
      isA<MenuAction>().having((e) => e.id, 'id', 'control.saveState'),
    );
    expect(
      entries[11],
      isA<MenuAction>().having((e) => e.id, 'id', 'control.loadState'),
    );
  });

  test('Device: Sound、Display、区切り、CPU Type、Boot Mode、'
      'オプションスイッチ3件を持つ（Bubilator88準拠でControlから移動）', () {
    final entries = catalog()
        .firstWhere((g) => g.id == MenuGroupId.device)
        .entries;
    expect(entries, hasLength(8));
    expect(
      entries[0],
      isA<MenuSubmenu>().having((e) => e.id, 'id', 'device.sound'),
    );
    expect(
      entries[1],
      isA<MenuSubmenu>().having((e) => e.id, 'id', 'device.display'),
    );
    expect(entries[2], isA<MenuSeparator>());
    final cpuTypeGroup = entries[3] as MenuRadioGroup<CpuType>;
    expect(cpuTypeGroup.id, 'device.cpuType');
    expect(cpuTypeGroup.options.map((o) => o.value), [
      CpuType.fast,
      CpuType.slow,
    ]);
    final bootModeGroup = entries[4] as MenuRadioGroup<BootMode>;
    expect(bootModeGroup.id, 'device.bootMode');
    expect(bootModeGroup.options.map((o) => o.value), [
      BootMode.basic,
      BootMode.dos,
    ]);
    expect(
      entries[5],
      isA<MenuCheckbox>().having((e) => e.id, 'id', 'device.cycleSteal'),
    );
    expect(
      entries[6],
      isA<MenuCheckbox>().having((e) => e.id, 'id', 'device.extendedRam'),
    );
    expect(
      entries[7],
      isA<MenuCheckbox>().having((e) => e.id, 'id', 'device.syncToHsync'),
    );
  });

  test('Control > Paste/Stop Pasteは自動キー入力中かどうかで有効・無効が入れ替わる（INP-03）', () {
    for (final isRunning in [true, false]) {
      for (final isAutoKeying in [true, false]) {
        final entries = catalog(
          isRunning: isRunning,
          isAutoKeying: isAutoKeying,
        ).firstWhere((g) => g.id == MenuGroupId.control).entries;
        final paste = entries[6] as MenuAction;
        final stopPaste = entries[7] as MenuAction;
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
    (entries[6] as MenuAction).onSelected();
    (entries[7] as MenuAction).onSelected();
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
      final checkbox = entries[8] as MenuCheckbox;
      expect(checkbox.checked, isTrue);
      checkbox.onChanged(false);
      expect(changed, isFalse);
    },
  );

  test('Deviceのオプションスイッチのチェック状態は引数に従う', () {
    final entries = catalog(
      optionSwitches: const RunOptionSwitches(
        cycleSteal: true,
        extendedRam: true,
        syncToHsync: true,
      ),
    ).firstWhere((g) => g.id == MenuGroupId.device).entries;
    expect((entries[5] as MenuCheckbox).checked, isTrue);
    expect((entries[6] as MenuCheckbox).checked, isTrue);
    expect((entries[7] as MenuCheckbox).checked, isTrue);
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

  test('CMT: Play/Rec/Eject、区切り、Play Button/Stop Button/Fast Forward/'
      'Fast Rewind、区切り、Waveform Shaper、区切り、Recentの順（原作.rc準拠）', () {
    final entries = catalog()
        .firstWhere((g) => g.id == MenuGroupId.cmt)
        .entries;
    expect(entries.map((e) => e.id), [
      'cmt.play',
      'cmt.rec',
      'cmt.eject',
      'cmt.sep0',
      'cmt.playButton',
      'cmt.stopButton',
      'cmt.fastForward',
      'cmt.fastRewind',
      'cmt.sep1',
      'cmt.waveShaper',
      'cmt.sep2',
      'cmt.recent',
    ]);
  });

  test('CMT: Ejectは媒体が挿入されているときだけ有効', () {
    final empty = catalog(cmtInserted: false)
        .firstWhere((g) => g.id == MenuGroupId.cmt)
        .entries;
    expect((empty[2] as MenuAction).enabled, isFalse);

    final inserted = catalog(cmtInserted: true)
        .firstWhere((g) => g.id == MenuGroupId.cmt)
        .entries;
    expect((inserted[2] as MenuAction).enabled, isTrue);
  });

  test('CMT: Play Button/Stop Buttonは走行状態に応じて有効・無効が入れ替わる', () {
    final stopped = catalog(
      cmtInserted: true,
      cmtPlaying: false,
      cmtRecording: false,
    ).firstWhere((g) => g.id == MenuGroupId.cmt).entries;
    expect((stopped[4] as MenuAction).enabled, isTrue); // playButton
    expect((stopped[5] as MenuAction).enabled, isFalse); // stopButton

    final playing = catalog(
      cmtInserted: true,
      cmtPlaying: true,
    ).firstWhere((g) => g.id == MenuGroupId.cmt).entries;
    expect((playing[4] as MenuAction).enabled, isFalse);
    expect((playing[5] as MenuAction).enabled, isTrue);
  });

  test('CMT: Waveform Shaperはチェック状態が引数に従う', () {
    final entries = catalog(
      cmtDriveSettings: const CmtDriveSettings(waveShaping: true),
    ).firstWhere((g) => g.id == MenuGroupId.cmt).entries;
    final checkbox =
        entries.firstWhere((e) => e.id == 'cmt.waveShaper') as MenuCheckbox;
    expect(checkbox.checked, isTrue);
  });

  test('CMT: Recentが空ならプレースホルダーを、あれば項目とClearを持つ', () {
    final empty =
        catalog()
                .firstWhere((g) => g.id == MenuGroupId.cmt)
                .entries
                .firstWhere((e) => e.id == 'cmt.recent')
            as MenuSubmenu;
    expect(empty.entries.map((e) => e.id), [
      'cmt.recent.empty',
      'cmt.recent.sep',
      'cmt.recent.clear',
    ]);
    expect((empty.entries[2] as MenuAction).enabled, isFalse);

    final withHistory =
        catalog(cmtRecentFiles: const [(token: 't1', displayName: 'TAPE.T77')])
                .firstWhere((g) => g.id == MenuGroupId.cmt)
                .entries
                .firstWhere((e) => e.id == 'cmt.recent')
            as MenuSubmenu;
    expect(withHistory.entries.map((e) => e.id), [
      'cmt.recent.t1',
      'cmt.recent.sep',
      'cmt.recent.clear',
    ]);
    expect((withHistory.entries[0] as MenuAction).label, 'TAPE.T77');
    expect((withHistory.entries[2] as MenuAction).enabled, isTrue);
  });

  test('Device: Sound、Displayの順で持つ（Bubilator88準拠でSoundはOPNのみ＋CMT音声3種）', () {
    final entries = catalog()
        .firstWhere((g) => g.id == MenuGroupId.device)
        .entries;
    final sound = entries[0] as MenuSubmenu;
    expect(sound.id, 'device.sound');
    // OPNラジオ、区切り、CMTノイズ/信号/音声、CMT音量ダイアログ。
    expect(sound.entries, hasLength(6));
    final radio = sound.entries[0] as MenuRadioGroup<String>;
    expect(radio.options.map((o) => o.label), ['OPN']);
    expect(sound.entries[1], isA<MenuSeparator>());
    expect(
      sound.entries[2],
      isA<MenuCheckbox>().having((e) => e.id, 'id', 'device.sound.cmtNoise'),
    );
    expect(
      sound.entries[3],
      isA<MenuCheckbox>().having((e) => e.id, 'id', 'device.sound.cmtSignal'),
    );
    expect(
      sound.entries[4],
      isA<MenuCheckbox>().having((e) => e.id, 'id', 'device.sound.cmtVoice'),
    );
    expect(
      sound.entries[5],
      isA<MenuAction>().having((e) => e.id, 'id', 'device.sound.cmtVolume'),
    );
    final display = entries[1] as MenuSubmenu;
    expect(display.id, 'device.display');
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

  test('Host: Rec Sound、Stop、Capture Screen、区切り、Screen、Sound、Input、'
      '区切り、Show Status Bar、Languageの順（Bubilator88準拠）', () {
    final entries = catalog()
        .firstWhere((g) => g.id == MenuGroupId.host)
        .entries;
    expect(entries, hasLength(10));
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
    expect(
      entries[5],
      isA<MenuSubmenu>().having((e) => e.id, 'id', 'host.sound'),
    );
    expect(
      entries[6],
      isA<MenuSubmenu>().having((e) => e.id, 'id', 'host.input'),
    );
    expect(entries[7], isA<MenuSeparator>());
    expect(
      entries[8],
      isA<MenuCheckbox>().having((e) => e.id, 'id', 'host.showStatusBar'),
    );
    expect(
      entries[9],
      isA<MenuSubmenu>().having((e) => e.id, 'id', 'host.language'),
    );
  });

  test('Host > Show Status Barは設定値をそのまま表示する', () {
    final checked =
        catalog(showStatusBar: true)
                .firstWhere((g) => g.id == MenuGroupId.host)
                .entries[8]
            as MenuCheckbox;
    expect(checked.checked, isTrue);
    final unchecked =
        catalog(showStatusBar: false)
                .firstWhere((g) => g.id == MenuGroupId.host)
                .entries[8]
            as MenuCheckbox;
    expect(unchecked.checked, isFalse);
  });

  test(
    'Host > Sound: FDD Mechanism Sound、Volumeの順（Bubilator88準拠でDeviceから移動）',
    () {
      final sound =
          catalog().firstWhere((g) => g.id == MenuGroupId.host).entries[5]
              as MenuSubmenu;
      expect(sound.entries, hasLength(2));
      final fddMechanismEnabled = sound.entries[0] as MenuCheckbox;
      expect(fddMechanismEnabled.id, 'host.sound.fddMechanismEnabled');
      final volume = sound.entries[1] as MenuAction;
      expect(volume.id, 'host.sound.volume');
    },
  );

  test('Host > Sound > VolumeはonOpenSoundVolumeを呼ぶ（AUD-03）', () {
    var called = false;
    final sound =
        catalog(onOpenSoundVolume: () => called = true)
                .firstWhere((g) => g.id == MenuGroupId.host)
                .entries[5]
            as MenuSubmenu;
    final volume = sound.entries[1] as MenuAction;
    expect(volume.enabled, isTrue);
    volume.onSelected();
    expect(called, isTrue);
  });

  test('Host > Sound > FDD Mechanism Soundはチェック状態に従いonFddMechanicalSoundEnabledChangedを呼ぶ（AUD-04）', () {
    bool? changed;
    final sound =
        catalog(
              fddMechanicalSoundEnabled: false,
              onFddMechanicalSoundEnabledChanged: (enabled) =>
                  changed = enabled,
            ).firstWhere((g) => g.id == MenuGroupId.host).entries[5]
            as MenuSubmenu;
    final checkbox = sound.entries[0] as MenuCheckbox;
    expect(checkbox.checked, isFalse);
    checkbox.onChanged(true);
    expect(changed, isTrue);
  });

  test('Host > Input: Joystickを持つ（INP-04、Bubilator88準拠でDeviceから移動）', () {
    final input =
        catalog().firstWhere((g) => g.id == MenuGroupId.host).entries[6]
            as MenuSubmenu;
    expect(input.entries, hasLength(1));
    final joystick = input.entries[0] as MenuAction;
    expect(joystick.id, 'host.input.joystick');
  });

  test('Host > Input > JoystickはonOpenJoystickAssignmentを呼ぶ（INP-04）', () {
    var called = false;
    final input =
        catalog(onOpenJoystickAssignment: () => called = true)
                .firstWhere((g) => g.id == MenuGroupId.host)
                .entries[6]
            as MenuSubmenu;
    final joystick = input.entries[0] as MenuAction;
    expect(joystick.enabled, isTrue);
    joystick.onSelected();
    expect(called, isTrue);
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

  test('Host > Screen > Windowは対応OSかつ倍率候補があるときだけラジオを出す', () {
    final unsupported = catalog(windowScaleSupported: false)
        .firstWhere((g) => g.id == MenuGroupId.host)
        .entries;
    final screenWithoutWindow = unsupported[4] as MenuSubmenu;
    expect(screenWithoutWindow.entries, hasLength(3));

    final supported = catalog(
      windowScaleSupported: true,
      windowScaleMultipliers: const [1, 2, 3],
      windowScaleCurrentMultiplier: 2,
    ).firstWhere((g) => g.id == MenuGroupId.host).entries;
    final screenWithWindow = supported[4] as MenuSubmenu;
    expect(screenWithWindow.entries, hasLength(4));
    final windowScale = screenWithWindow.entries[0] as MenuRadioGroup<int>;
    expect(windowScale.id, 'host.screen.windowScale');
    expect(windowScale.options.map((o) => o.value), [1, 2, 3]);
    expect(windowScale.groupValue, 2);
    expect(
      screenWithWindow.entries[1],
      isA<MenuCheckbox>().having((e) => e.id, 'id', 'host.screen.fullscreen'),
    );
  });

  test('Host > Screen > Windowはフルスクリーン中は選択中の値を保ったまま操作不可', () {
    final entries = catalog(
      windowScaleSupported: true,
      windowScaleMultipliers: const [1, 2, 3],
      windowScaleCurrentMultiplier: 2,
      isFullscreen: true,
    ).firstWhere((g) => g.id == MenuGroupId.host).entries;
    final screen = entries[4] as MenuSubmenu;
    final windowScale = screen.entries[0] as MenuRadioGroup<int>;

    expect(windowScale.groupValue, 2);
    expect(windowScale.options.every((o) => !o.enabled), isTrue);
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
    final language = host[9] as MenuSubmenu;
    final mode = language.entries.single as MenuRadioGroup<AppLocaleMode>;
    expect(mode.options.map((o) => o.value), [
      AppLocaleMode.system,
      AppLocaleMode.english,
      AppLocaleMode.japanese,
    ]);
  });
}
