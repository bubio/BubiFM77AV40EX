import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/display/fullscreen_controller.dart';
import '../features/display/screenshot_service.dart';
import '../features/session/rom_boot_decision.dart';
import '../features/session/rom_settings_state.dart';
import '../features/session/session_providers.dart';
import '../features/session/widgets/emulator_view.dart';
import '../features/session/widgets/rom_problem_dialog.dart';
import '../features/settings/settings_controller.dart';
import '../features/settings/settings_state.dart';
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
      fddMechanicalSoundEnabled: emulator.fddMechanicalSoundEnabled,
      onFddMechanicalSoundEnabledChanged:
          emulatorController.setFddMechanicalSoundEnabled,
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
        ref
            .read(emulatorControllerProvider.notifier)
            .launch(bootMode: next.bootMode);
      case RomBootAction.showProblem:
        _showRomProblemDialog();
      case RomBootAction.none:
        break;
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
