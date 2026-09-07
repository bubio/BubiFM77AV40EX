import 'package:bubi_fm77av40ex/app/l10n/generated/app_localizations.dart';
import 'package:bubi_fm77av40ex/app/l10n/generated/app_localizations_en.dart';
import 'package:bubi_fm77av40ex/app/menu/app_menu_bar.dart';
import 'package:bubi_fm77av40ex/app/menu/menu_catalog.dart';
import 'package:bubi_fm77av40ex/app/menu/menu_command.dart';
import 'package:bubi_fm77av40ex/emulator/session_state.dart';
import 'package:bubi_fm77av40ex/features/display/screen_filter.dart';
import 'package:bubi_fm77av40ex/features/display/screen_fit.dart';
import 'package:bubi_fm77av40ex/features/settings/settings_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [AppMenuBar]の実際のタップ操作を検証する（[buildMenuCatalog]の構造契約
/// だけを見る`menu_catalog_test.dart`と違い、Widgetを組み立てて操作する）。
///
/// `MenuRadioGroup<T>`は`BootMode`や`ScreenFit`など呼び出しごとに異なる
/// `T`を持つが、`AppMenuBar._build`は`MenuEntry`という共通の型なし構造を
/// 走査するため、パターンマッチの時点で`T`が`dynamic`へ消える。この消えた
/// `T`のまま`RadioMenuButton<T>`を作ると、フィールドに実際に入っている
/// 関数の型（例:`void Function(BootMode)`）と食い違い、選択のたびに
/// 実行時`TypeError`でコールバックが起きずに終わる
/// （利用者から見ると「選択しても切り替わらない」）。
void main() {
  final AppLocalizations l10n = AppLocalizationsEn();

  List<MenuGroup> buildCatalog({
    void Function(ScreenFit fit)? onScreenFitChanged,
    void Function(BootMode mode)? onBootModeChanged,
    void Function(int multiplier)? onSpeedMultiplierChanged,
    void Function(bool enabled)? onFullSpeedChanged,
    void Function(CpuType type)? onCpuTypeChanged,
    void Function(RunOptionSwitches switches)? onOptionSwitchesChanged,
    void Function(AppLocaleMode mode)? onLocaleModeChanged,
    RunOptionSwitches optionSwitches = const RunOptionSwitches(),
  }) {
    return buildMenuCatalog(
      l10n: l10n,
      isRunning: true,
      onReset: (_) {},
      bootMode: BootMode.basic,
      onBootModeChanged: onBootModeChanged ?? (_) {},
      speedMultiplier: SpeedMultiplier.x1,
      onSpeedMultiplierChanged: onSpeedMultiplierChanged ?? (_) {},
      fullSpeed: false,
      onFullSpeedChanged: onFullSpeedChanged ?? (_) {},
      cpuType: CpuType.fast,
      onCpuTypeChanged: onCpuTypeChanged ?? (_) {},
      optionSwitches: optionSwitches,
      onOptionSwitchesChanged: onOptionSwitchesChanged ?? (_) {},
      fddMedia: const {},
      onFddInsert: (_) {},
      onFddEject: (_) {},
      fddDriveSettings: const {},
      onFddWriteProtectChanged: (_, _) {},
      onFddTimingChanged: (_, _) {},
      onFddCrcCheckChanged: (_, _) {},
      onFddInsertBlank: (_, _) {},
      fddBankNum: const {},
      fddCurBank: const {},
      onFddBankChanged: (_, _) {},
      fddSourceKind: const {},
      onFddSaveAs: (_) {},
      fddRecentFiles: const {},
      onFddInsertFromRecent: (_, _) {},
      onFddClearRecentFiles: (_) {},
      screenFit: ScreenFit.aspect,
      onScreenFitChanged: onScreenFitChanged ?? (_) {},
      scanlineEnabled: false,
      onScanlineChanged: (_) {},
      hostFilter: HostScreenFilter.none,
      onHostFilterChanged: (_) {},
      isFullscreen: false,
      fullscreenSupported: false,
      onFullscreenChanged: (_) {},
      onCaptureScreen: () {},
      isRecording: false,
      onStartRecording: () {},
      onStopRecording: () {},
      onOpenSoundVolume: () {},
      fddMechanicalSoundEnabled: true,
      onFddMechanicalSoundEnabledChanged: (_) {},
      isAutoKeying: false,
      onStartAutoKey: () {},
      onStopAutoKey: () {},
      romajiToKana: false,
      onRomajiToKanaChanged: (_) {},
      onOpenSaveState: () {},
      onOpenLoadState: () {},
      localeMode: AppLocaleMode.system,
      onLocaleModeChanged: onLocaleModeChanged ?? (_) {},
    );
  }

  testWidgets('Host > Screen > Display > Fill the areaで選択が伝わる', (tester) async {
    ScreenFit? changedTo;

    final groups = buildCatalog(onScreenFitChanged: (fit) => changedTo = fit);

    await tester.pumpWidget(
      MaterialApp(
        home: AppMenuBar(groups: groups, child: const SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Host'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Screen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Display'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Fill the area'));
    await tester.pumpAndSettle();

    expect(changedTo, ScreenFit.fill);
  });

  testWidgets('Control > Boot mode > DOSで選択が伝わる', (tester) async {
    BootMode? changedTo;

    final groups = buildCatalog(onBootModeChanged: (mode) => changedTo = mode);

    await tester.pumpWidget(
      MaterialApp(
        home: AppMenuBar(groups: groups, child: const SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Control'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Boot mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('DOS'));
    await tester.pumpAndSettle();

    expect(changedTo, BootMode.dos);
  });

  testWidgets('Control > CPU Speed > x4で選択が伝わる', (tester) async {
    int? changedTo;

    final groups = buildCatalog(
      onSpeedMultiplierChanged: (multiplier) => changedTo = multiplier,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppMenuBar(groups: groups, child: const SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Control'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CPU Speed'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('x4'));
    await tester.pumpAndSettle();

    expect(changedTo, SpeedMultiplier.x4);
  });

  testWidgets('Control > CPU Type > 1.2MHzで選択が伝わる', (tester) async {
    CpuType? changedTo;

    final groups = buildCatalog(onCpuTypeChanged: (type) => changedTo = type);

    await tester.pumpWidget(
      MaterialApp(
        home: AppMenuBar(groups: groups, child: const SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Control'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('CPU Type'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1.2MHz'));
    await tester.pumpAndSettle();

    expect(changedTo, CpuType.slow);
  });

  testWidgets('Control > Cycle Stealのチェックで選択が伝わる', (tester) async {
    RunOptionSwitches? changedTo;

    final groups = buildCatalog(
      onOptionSwitchesChanged: (switches) => changedTo = switches,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppMenuBar(groups: groups, child: const SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Control'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cycle Steal'));
    await tester.pumpAndSettle();

    expect(changedTo, const RunOptionSwitches(cycleSteal: true));
  });

  testWidgets('Control > Full Speedのチェックで選択が伝わる', (tester) async {
    bool? changedTo;

    final groups = buildCatalog(
      onFullSpeedChanged: (enabled) => changedTo = enabled,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppMenuBar(groups: groups, child: const SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Control'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Full Speed'));
    await tester.pumpAndSettle();

    expect(changedTo, isTrue);
  });

  testWidgets('Host > Language > System > Englishで選択が伝わる', (tester) async {
    AppLocaleMode? changedTo;

    final groups = buildCatalog(
      onLocaleModeChanged: (mode) => changedTo = mode,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: AppMenuBar(groups: groups, child: const SizedBox()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Host'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    // ラジオ群のlabelは空のため、サブメニューの表示名は現在の選択値
    // （既定はSystem）になる（design.md 12.3、menu_catalog.dart）。
    await tester.tap(find.text('System'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(changedTo, AppLocaleMode.english);
  });
}
