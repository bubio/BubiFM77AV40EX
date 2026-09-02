import 'package:bubi_fm77av40ex/app/l10n/generated/app_localizations.dart';
import 'package:bubi_fm77av40ex/app/l10n/generated/app_localizations_en.dart';
import 'package:bubi_fm77av40ex/app/menu/app_menu_bar.dart';
import 'package:bubi_fm77av40ex/app/menu/menu_catalog.dart';
import 'package:bubi_fm77av40ex/emulator/session_state.dart';
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
  testWidgets('Host > Screen > Display > Fill the areaで選択が伝わる', (tester) async {
    final AppLocalizations l10n = AppLocalizationsEn();
    ScreenFit? changedTo;

    final groups = buildMenuCatalog(
      l10n: l10n,
      isRunning: true,
      onReset: (_) {},
      bootMode: BootMode.basic,
      onBootModeChanged: (_) {},
      fddMedia: const {},
      onFddInsert: (_) {},
      onFddEject: (_) {},
      screenFit: ScreenFit.aspect,
      onScreenFitChanged: (fit) => changedTo = fit,
      localeMode: AppLocaleMode.system,
      onLocaleModeChanged: (_) {},
    );

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
    final AppLocalizations l10n = AppLocalizationsEn();
    BootMode? changedTo;

    final groups = buildMenuCatalog(
      l10n: l10n,
      isRunning: true,
      onReset: (_) {},
      bootMode: BootMode.basic,
      onBootModeChanged: (mode) => changedTo = mode,
      fddMedia: const {},
      onFddInsert: (_) {},
      onFddEject: (_) {},
      screenFit: ScreenFit.aspect,
      onScreenFitChanged: (_) {},
      localeMode: AppLocaleMode.system,
      onLocaleModeChanged: (_) {},
    );

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

  testWidgets('Host > Language > System > Englishで選択が伝わる', (tester) async {
    final AppLocalizations l10n = AppLocalizationsEn();
    AppLocaleMode? changedTo;

    final groups = buildMenuCatalog(
      l10n: l10n,
      isRunning: true,
      onReset: (_) {},
      bootMode: BootMode.basic,
      onBootModeChanged: (_) {},
      fddMedia: const {},
      onFddInsert: (_) {},
      onFddEject: (_) {},
      screenFit: ScreenFit.aspect,
      onScreenFitChanged: (_) {},
      localeMode: AppLocaleMode.system,
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
