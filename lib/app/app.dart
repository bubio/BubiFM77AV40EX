import 'dart:async';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/display/fullscreen_controller.dart';
import '../features/display/screenshot_service.dart';
import '../features/input/joystick_assignment_controller.dart';
import '../features/input/joystick_assignment_dialog.dart';
import '../features/session/emulator_controller.dart';
import '../features/session/rom_boot_decision.dart';
import '../features/session/rom_settings_state.dart';
import '../features/session/session_providers.dart';
import '../features/session/widgets/emulator_view.dart';
import '../features/session/widgets/rom_problem_dialog.dart';
import '../features/settings/settings_controller.dart';
import '../features/settings/settings_state.dart';
import '../features/state/state_slot_dialog.dart';
import 'cli_args.dart';
import 'l10n/generated/app_localizations.dart';
import 'l10n/generated/app_localizations_en.dart';
import 'l10n/generated/app_localizations_ja.dart';
import 'menu/app_menu_bar.dart';
import 'menu/menu_catalog.dart';
import 'menu/platform_application_menu.dart';
import 'menu/settings_dialog.dart';
import 'menu/sound_volume_dialog.dart';

/// アプリケーションのルート。
///
/// macOS標準Applicationメニュー（About、Settings、Services、Hide系、
/// Quit）は[PlatformApplicationMenu]がここで一度だけ組み立てる
/// （design.md 12.1）。`Control / Disk / Device / Host`のアプリ内メニューは
/// [_Home]が[buildMenuCatalog]から組み立てる。featureは`app`へ依存しない
/// （design.md 3.1）ため、カタログの組み立ては`app`側に置く。
class BubiFm77Av40ExApp extends ConsumerWidget {
  const BubiFm77Av40ExApp({super.key});

  static final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsControllerProvider);
    final settingsController = ref.read(settingsControllerProvider.notifier);
    final l10n = _syncLocalizationsFor(settings.localeMode);

    final materialApp = MaterialApp(
      navigatorKey: _navigatorKey,
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      locale: _localeOf(settings.localeMode),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const _Home(),
    );

    if (!Platform.isMacOS) {
      return materialApp;
    }
    return PlatformApplicationMenu(
      l10n: l10n,
      onSettings: () {
        final dialogContext = _navigatorKey.currentContext;
        if (dialogContext == null) {
          return;
        }
        showDialog<void>(
          context: dialogContext,
          builder: (context) => SettingsDialog(
            l10n: AppLocalizations.of(context),
            localeMode: settings.localeMode,
            onLocaleModeChanged: settingsController.setLocaleMode,
            masterVolume: settings.masterVolume,
            onMasterVolumeChanged: settingsController.setMasterVolume,
          ),
        );
      },
      onQuit: () async {
        await ref.read(emulatorControllerProvider.notifier).shutdown();
        exit(0);
      },
      child: materialApp,
    );
  }

  static Locale? _localeOf(AppLocaleMode mode) {
    return switch (mode) {
      AppLocaleMode.system => null,
      AppLocaleMode.english => const Locale('en'),
      AppLocaleMode.japanese => const Locale('ja'),
    };
  }

  /// macOS標準Applicationメニューのラベル用。`MaterialApp`の外側に置くため
  /// `Localizations`の非同期読み込みへ頼らず、生成済みの言語別実装を
  /// 直接選ぶ（design.md 12.3「日英切替時は…実行中に反映する」）。
  static AppLocalizations _syncLocalizationsFor(AppLocaleMode mode) {
    final languageCode = switch (mode) {
      AppLocaleMode.system => PlatformDispatcher.instance.locale.languageCode,
      AppLocaleMode.english => 'en',
      AppLocaleMode.japanese => 'ja',
    };
    return languageCode == 'ja' ? AppLocalizationsJa() : AppLocalizationsEn();
  }
}

/// 起動直後に保存済みのROM設定を復元してから画面を出す。
class _Home extends ConsumerStatefulWidget {
  const _Home();

  @override
  ConsumerState<_Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<_Home> {
  /// 二重に`showDialog`しないためのガード（design.md 301）。
  bool _romDialogShowing = false;

  /// CLI（APP-05）由来の実行設定・媒体挿入を最初の起動時にだけ適用する
  /// ためのガード。
  bool _cliOverridesApplied = false;
  bool _cliMediaApplied = false;

  @override
  void initState() {
    super.initState();
    // 復元は失敗しても画面を出す。アクセス権の失効と走査の失敗は
    // Controllerが状態として持ち、ダイアログへ出す。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(romSettingsControllerProvider.notifier).restore();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final emulator = ref.watch(emulatorControllerProvider);
    final emulatorController = ref.read(emulatorControllerProvider.notifier);
    final romSettings = ref.watch(romSettingsControllerProvider);
    final romSettingsController = ref.read(
      romSettingsControllerProvider.notifier,
    );
    final settings = ref.watch(settingsControllerProvider);
    final settingsController = ref.read(settingsControllerProvider.notifier);
    final fullscreen = ref.watch(fullscreenControllerProvider);
    final fullscreenController = ref.read(
      fullscreenControllerProvider.notifier,
    );

    // ROM走査が終わるたびに、自動起動するかROM問題ダイアログを出すかを
    // 判定する（`rom_boot_decision.dart`）。初期画面はエミュレーター表示を
    // 中心に置き、ROM設定用の別画面は持たない（design.md 301）。
    ref.listen(romSettingsControllerProvider, (previous, next) {
      _syncWithRomSettings(next);
    });

    // ジョイスティック割当（M3 INP-04）の入力状態変化をコアへ転送する。
    // JoystickAssignmentControllerはコアを知らず、EmulatorControllerも
    // 物理コントローラーを知らないため、他のcontroller間連携
    // （_syncWithRomSettings）と同じくここで橋渡しする（design.md 3.1）。
    ref.listen(joystickAssignmentControllerProvider, (previous, next) {
      for (final entry in next.bits.entries) {
        if (previous?.bits[entry.key] != entry.value) {
          emulatorController.setJoystickState(entry.key, entry.value);
        }
      }
    });

    final menuGroups = buildMenuCatalog(
      l10n: l10n,
      isRunning: emulator.isRunning,
      onReset: (kind) =>
          emulatorController.reset(kind, bootMode: romSettings.bootMode),
      bootMode: romSettings.bootMode,
      onBootModeChanged: romSettingsController.setBootMode,
      speedMultiplier: emulator.speedMultiplier,
      onSpeedMultiplierChanged: emulatorController.setSpeedMultiplier,
      fullSpeed: emulator.fullSpeed,
      onFullSpeedChanged: emulatorController.setFullSpeed,
      cpuType: emulator.cpuType,
      onCpuTypeChanged: emulatorController.setCpuType,
      optionSwitches: emulator.optionSwitches,
      onOptionSwitchesChanged: emulatorController.setRunOptionSwitches,
      fddMedia: emulator.fddMedia,
      onFddInsert: emulatorController.insertFdd,
      onFddEject: emulatorController.ejectFdd,
      fddDriveSettings: emulator.fddDriveSettings,
      onFddWriteProtectChanged: emulatorController.setFddWriteProtect,
      onFddTimingChanged: emulatorController.setFddTiming,
      onFddCrcCheckChanged: emulatorController.setFddCrcCheck,
      onFddInsertBlank: emulatorController.insertBlankFdd,
      fddBankNum: emulator.fddBankNum,
      fddCurBank: emulator.fddCurBank,
      onFddBankChanged: emulatorController.insertFddBank,
      fddSourceKind: emulator.fddSourceKind,
      onFddSaveAs: emulatorController.saveFddAs,
      fddRecentFiles: emulator.fddRecentFiles,
      onFddInsertFromRecent: emulatorController.insertFddFromRecent,
      onFddClearRecentFiles: emulatorController.clearRecentFiles,
      screenFit: emulator.fit,
      onScreenFitChanged: emulatorController.setFit,
      scanlineEnabled: emulator.scanlineEnabled,
      onScanlineChanged: emulatorController.setScanlineEnabled,
      hostFilter: emulator.hostFilter,
      onHostFilterChanged: emulatorController.setHostFilter,
      isFullscreen: fullscreen.isFullscreen,
      fullscreenSupported: fullscreen.supported,
      onFullscreenChanged: fullscreenController.setFullscreen,
      onCaptureScreen: _captureScreen,
      isRecording: emulator.isRecording,
      onStartRecording: emulatorController.startRecording,
      onStopRecording: emulatorController.stopRecording,
      onOpenSoundVolume: _openSoundVolumeDialog,
      onOpenJoystickAssignment: _openJoystickAssignmentDialog,
      fddMechanicalSoundEnabled: emulator.fddMechanicalSoundEnabled,
      onFddMechanicalSoundEnabledChanged:
          emulatorController.setFddMechanicalSoundEnabled,
      isAutoKeying: emulator.isAutoKeying,
      onStartAutoKey: emulatorController.startAutoKey,
      onStopAutoKey: emulatorController.stopAutoKey,
      romajiToKana: emulator.romajiToKana,
      onRomajiToKanaChanged: emulatorController.setRomajiToKana,
      onOpenSaveState: () => _openStateSlotDialog(StateSlotDialogMode.save),
      onOpenLoadState: () => _openStateSlotDialog(StateSlotDialogMode.load),
      localeMode: settings.localeMode,
      onLocaleModeChanged: settingsController.setLocaleMode,
    );

    return AppMenuBar(groups: menuGroups, child: const EmulatorView());
  }

  void _syncWithRomSettings(RomSettingsState next) {
    final action = decideRomBootAction(
      emulatorSession: ref.read(emulatorControllerProvider).session,
      romSettings: next,
    );
    switch (action) {
      case RomBootAction.launch:
        final cli = ref.read(cliOptionsProvider);
        final controller = ref.read(emulatorControllerProvider.notifier);
        if (!_cliOverridesApplied) {
          _cliOverridesApplied = true;
          _applyCliRuntimeOverrides(controller, cli);
        }
        final bootMode = cli.bootMode ?? next.bootMode;
        unawaited(
          controller.launch(bootMode: bootMode).then((_) {
            if (mounted) {
              _applyCliMediaIfNeeded(controller, cli);
            }
          }),
        );
      case RomBootAction.showProblem:
        _showRomProblemDialog();
      case RomBootAction.none:
        break;
    }
  }

  /// CLI（APP-05）が指定したCPU種別・速度・オプションスイッチを、
  /// `launch()`より前に適用する。既存の「次回`launch()`にも再適用できる
  /// よう覚える」仕組み（SYS-03/05/06）にそのまま乗せる。
  void _applyCliRuntimeOverrides(
    EmulatorController controller,
    CliOptions cli,
  ) {
    if (!cli.hasRuntimeOverrides) {
      return;
    }
    if (cli.cpuType != null) {
      controller.setCpuType(cli.cpuType!);
    }
    if (cli.speedMultiplier != null) {
      controller.setSpeedMultiplier(cli.speedMultiplier!);
    }
    if (cli.fullSpeed) {
      controller.setFullSpeed(true);
    }
    if (cli.cycleSteal != null ||
        cli.extendedRam != null ||
        cli.syncToHsync != null) {
      final current = ref.read(emulatorControllerProvider).optionSwitches;
      controller.setRunOptionSwitches(
        current.copyWith(
          cycleSteal: cli.cycleSteal,
          extendedRam: cli.extendedRam,
          syncToHsync: cli.syncToHsync,
        ),
      );
    }
  }

  /// CLI（APP-05）が指定した媒体をFD1(0)→FD2(1)の順に一度だけ挿入する。
  ///
  /// 単一image-fileでバンク省略時、挿入結果が複数バンクなら同じファイルの
  /// バンク2をFD2へも挿入する（specification.md 7.9）。バンク番号が実際に
  /// そのファイルに存在しないなど、GUI起動後にしか分からない媒体エラーは
  /// この時点でexit(3)する（design.md「CLI（APP-05）の実装方式」の既知の
  /// 制約）。
  Future<void> _applyCliMediaIfNeeded(
    EmulatorController controller,
    CliOptions cli,
  ) async {
    if (_cliMediaApplied || cli.media.isEmpty) {
      return;
    }
    _cliMediaApplied = true;
    for (var drive = 0; drive < cli.media.length; drive++) {
      final spec = cli.media[drive];
      final bank = (spec.bank ?? 1) - 1;
      final ok = await controller.insertFddFromCliPath(
        drive,
        spec.path,
        bank: bank,
      );
      if (!mounted) {
        return;
      }
      if (!ok) {
        stderr.writeln('Media error: failed to insert "${spec.path}".');
        exit(3);
      }
    }
    if (cli.media.length == 1 && cli.media.first.bank == null) {
      final bankNum = ref.read(emulatorControllerProvider).fddBankNum[0] ?? 1;
      if (bankNum > 1) {
        final ok = await controller.insertFddFromCliPath(
          1,
          cli.media.first.path,
          bank: 1,
        );
        if (mounted && !ok) {
          stderr.writeln(
            'Media error: failed to insert "${cli.media.first.path}" (bank 2) into FD2.',
          );
          exit(3);
        }
      }
    }
  }

  /// 画面を保存する（VID-05）。失敗は単発の便利機能のためログのみとし、
  /// 利用者へは出さない（development_plan.md「表示」進捗の判断）。
  Future<void> _captureScreen() async {
    final key = ref.read(screenshotBoundaryKeyProvider);
    final service = ref.read(screenshotServiceProvider);
    try {
      await service.capture(key);
    } on ScreenshotException catch (error) {
      debugPrint('Screenshot failed: $error');
    }
  }

  /// 標準音声チャンネルの音量ダイアログを開く（AUD-03）。
  ///
  /// [SettingsDialog]（マスター音量）と同じく、開いた時点の値を渡すだけの
  /// `StatelessWidget`にする。スライダーを動かすたびに`_HomeState`が
  /// 再構築されても、すでに開いているダイアログ自体は作り直さない
  /// （design.md 12.3、既存のマスター音量ダイアログと同じ制約）。
  void _openSoundVolumeDialog() {
    final controller = ref.read(emulatorControllerProvider.notifier);
    showDialog<void>(
      context: context,
      builder: (context) => SoundVolumeDialog(
        l10n: AppLocalizations.of(context),
        volumes: ref.read(emulatorControllerProvider).soundVolumes,
        onChanged: (channel, volume) {
          controller.setSoundChannelVolume(channel, volume);
        },
      ),
    );
  }

  /// 状態スロットのグリッドダイアログを開く（STA-01/STA-02）。
  void _openStateSlotDialog(StateSlotDialogMode mode) {
    showDialog<void>(
      context: context,
      builder: (context) => StateSlotDialog(mode: mode),
    );
  }

  /// ジョイスティック割当ダイアログを開く（M3 INP-04）。
  void _openJoystickAssignmentDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => const JoystickAssignmentDialog(),
    );
  }

  void _showRomProblemDialog() {
    if (_romDialogShowing || !mounted) {
      return;
    }
    _romDialogShowing = true;
    showDialog<void>(
      context: context,
      builder: (context) => const RomProblemDialog(),
    ).whenComplete(() => _romDialogShowing = false);
  }
}
