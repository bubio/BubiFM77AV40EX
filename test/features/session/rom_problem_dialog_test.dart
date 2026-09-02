import 'package:bubi_fm77av40ex/app/l10n/generated/app_localizations.dart';
import 'package:bubi_fm77av40ex/emulator/session_state.dart';
import 'package:bubi_fm77av40ex/features/session/emulator_controller.dart';
import 'package:bubi_fm77av40ex/features/session/rom_settings_controller.dart';
import 'package:bubi_fm77av40ex/features/session/session_providers.dart';
import 'package:bubi_fm77av40ex/features/session/widgets/rom_problem_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// [RomProblemDialog]は`decideRomBootAction`が`showProblem`を返した場合
/// だけ`app.dart`の`_Home`が開く（`rom_boot_decision_test.dart`で分岐は
/// 検証済み）。ここではダイアログ自体の内容と、起動が始まったら自動で
/// 閉じることを確認する（APP-06、design.md 301）。
void main() {
  late FakePreferencesStore preferences;
  late FakeAppDataPaths appDataPaths;
  late FakeRomScanner scanner;
  late FakeEmulatorSession session;

  setUp(() {
    preferences = FakePreferencesStore();
    appDataPaths = FakeAppDataPaths();
    scanner = FakeRomScanner();
    session = FakeEmulatorSession();
  });

  Future<ProviderContainer> wrap(WidgetTester tester, Locale locale) async {
    final container = ProviderContainer(
      overrides: [
        romSettingsControllerProvider.overrideWith(
          () => RomSettingsController(
            appDataPaths: appDataPaths,
            preferences: preferences,
            scanner: scanner,
            revealFolder: (path) async {},
          ),
        ),
        emulatorControllerProvider.overrideWith(
          () => EmulatorController(
            appDataPaths: appDataPaths,
            externalFileAccess: FakeExternalFileAccess(),
            cacheWorkspace: FakeCacheWorkspace(),
            createSession: ({
              required String homeDir,
              String? romDir,
              BootMode bootMode = BootMode.basic,
            }) => session,
          ),
        ),
      ],
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                key: const Key('openRomProblemDialog'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => const RomProblemDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('openRomProblemDialog')));
    await tester.pumpAndSettle();
  }

  testWidgets('起動必須ROMの不足をファイル単位で表示する', (tester) async {
    // 起動必須のうち EXTSUB.ROM だけが欠けている。
    scanner.result = bootRequiredProbes()
      ..removeWhere((probe) => probe.fileName == 'EXTSUB.ROM');

    final container = await wrap(tester, const Locale('ja'));
    await container.read(romSettingsControllerProvider.notifier).restore();
    await tester.pumpAndSettle();
    await openDialog(tester);

    expect(find.text('起動できません。起動必須ROMを確認してください。'), findsOneWidget);
    final row = find.byKey(const Key('romEntry_extsub'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('EXTSUB.ROM')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('見つかりません')),
      findsOneWidget,
    );
  });

  testWidgets('走査自体が失敗したときの表示', (tester) async {
    scanner.throwOnScan = Exception('読み取れません');

    final container = await wrap(tester, const Locale('ja'));
    await container.read(romSettingsControllerProvider.notifier).restore();
    await tester.pumpAndSettle();
    await openDialog(tester);

    expect(
      find.text('ROMフォルダーを読み取れませんでした。フォルダーとアクセス権を確認してください。'),
      findsOneWidget,
    );
  });

  testWidgets('フォルダーの位置と「フォルダーを開く」ボタンを出す', (tester) async {
    scanner.result = const [];

    final container = await wrap(tester, const Locale('ja'));
    await container.read(romSettingsControllerProvider.notifier).restore();
    await tester.pumpAndSettle();
    await openDialog(tester);

    final path = tester.widget<Text>(find.byKey(const Key('romDirectoryPath')));
    expect(path.data, '/data/BubiFM77AV40EX/roms');
    expect(find.text('フォルダーを開く'), findsOneWidget);
  });

  testWidgets('英語ロケールでも同じ内容を出す', (tester) async {
    scanner.result = const [];

    final container = await wrap(tester, const Locale('en'));
    await container.read(romSettingsControllerProvider.notifier).restore();
    await tester.pumpAndSettle();
    await openDialog(tester);

    expect(
      find.text('Cannot start. Check the required boot ROMs.'),
      findsOneWidget,
    );
  });

  testWidgets('起動が始まると開いていたダイアログが自動で閉じる', (tester) async {
    scanner.result = const [];

    final container = await wrap(tester, const Locale('ja'));
    await container.read(romSettingsControllerProvider.notifier).restore();
    await tester.pumpAndSettle();
    await openDialog(tester);
    expect(find.byType(RomProblemDialog), findsOneWidget);

    // 再検証で解決した想定で、直接launch()する
    // （FakeEmulatorSession.stateは既定でrunning）。
    await container.read(emulatorControllerProvider.notifier).launch();
    await tester.pumpAndSettle();

    expect(find.byType(RomProblemDialog), findsNothing);
    container.dispose();
  });
}
