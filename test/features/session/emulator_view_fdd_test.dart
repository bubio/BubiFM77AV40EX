import 'package:bubi_fm77av40ex/app/l10n/generated/app_localizations.dart';
import 'package:bubi_fm77av40ex/app/menu/app_menu_bar.dart';
import 'package:bubi_fm77av40ex/app/menu/menu_catalog.dart';
import 'package:bubi_fm77av40ex/emulator/session_state.dart';
import 'package:bubi_fm77av40ex/features/session/emulator_controller.dart';
import 'package:bubi_fm77av40ex/features/session/rom_settings_controller.dart';
import 'package:bubi_fm77av40ex/features/session/session_providers.dart';
import 'package:bubi_fm77av40ex/features/session/widgets/emulator_view.dart';
import 'package:bubi_fm77av40ex/features/settings/settings_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// 起動直後に`launch()`する薄いホスト。`app.dart`の`_Home`相当。
///
/// FD1/FD2の挿入・排出はDiskメニュー（`Control / Disk / Device / Host`、
/// design.md 12.2）から行う。下部ツールバーのボタンは廃止した
/// （オリジナルのGUIを踏襲し、メニュー・ステータスバー以外の独自UIを
/// 持たない方針）。
class _LaunchingHome extends ConsumerStatefulWidget {
  const _LaunchingHome();

  @override
  ConsumerState<_LaunchingHome> createState() => _LaunchingHomeState();
}

class _LaunchingHomeState extends ConsumerState<_LaunchingHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(emulatorControllerProvider.notifier).launch();
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

    final menuGroups = buildMenuCatalog(
      l10n: l10n,
      isRunning: emulator.isRunning,
      onReset: emulatorController.reset,
      bootMode: romSettings.bootMode,
      onBootModeChanged: romSettingsController.setBootMode,
      fddMedia: emulator.fddMedia,
      onFddInsert: emulatorController.insertFdd,
      onFddEject: emulatorController.ejectFdd,
      screenFit: emulator.fit,
      onScreenFitChanged: emulatorController.setFit,
      localeMode: settings.localeMode,
      onLocaleModeChanged: settingsController.setLocaleMode,
    );

    return AppMenuBar(groups: menuGroups, child: const EmulatorView());
  }
}

/// FDD-01のDiskメニュー（design.md 12.2）からの挿入・排出操作を確かめる。
void main() {
  late FakeEmulatorSession session;
  late FakeExternalFileAccess externalFileAccess;
  late FakeCacheWorkspace cacheWorkspace;
  late FakePreferencesStore preferences;

  setUp(() {
    session = FakeEmulatorSession();
    externalFileAccess = FakeExternalFileAccess();
    cacheWorkspace = FakeCacheWorkspace();
    preferences = FakePreferencesStore();
  });

  // `addTearDown`はテスト本体の後、Flutter testのpending timer検査より
  // 後に走る。`EmulatorController`の`Timer.periodic`（design.md 12.4の
  // FPS観測）をその検査までに確実に止めるため、containerの破棄は
  // 各試験の最後で明示的に呼ぶ。
  Future<ProviderContainer> wrap(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        emulatorControllerProvider.overrideWith(
          () => EmulatorController(
            appDataPaths: FakeAppDataPaths(),
            externalFileAccess: externalFileAccess,
            cacheWorkspace: cacheWorkspace,
            createSession: ({
              required String homeDir,
              String? romDir,
              BootMode bootMode = BootMode.basic,
            }) => session,
          ),
        ),
        romSettingsControllerProvider.overrideWith(
          () => RomSettingsController(
            appDataPaths: FakeAppDataPaths(),
            preferences: preferences,
            scanner: FakeRomScanner(),
          ),
        ),
        settingsControllerProvider.overrideWith(
          () => SettingsController(preferences: preferences),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const _LaunchingHome(),
        ),
      ),
    );
    return container;
  }

  Future<void> openFd1Menu(WidgetTester tester) async {
    await tester.tap(find.text('Disk'));
    await tester.pumpAndSettle();
    // StatusBarにも"FD1"ラベルがあるため、Text('FD1')を直接の`child`に
    // 持つDiskメニューのサブメニューボタンだけをピンポイントで狙う
    // （`widgetWithText`はancestor全体を拾うため、Diskの根自体も
    // 一致してしまう）。
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is SubmenuButton &&
            widget.child is Text &&
            (widget.child! as Text).data == 'FD1',
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('FDD-01 Diskメニューから挿入すると状態へ媒体名を持つ', (tester) async {
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/GAME.D88',
      displayName: 'GAME.D88',
    );

    final container = await wrap(tester);
    await tester.pumpAndSettle();

    await openFd1Menu(tester);
    await tester.tap(find.text('挿入…'));
    await tester.pumpAndSettle();

    expect(container.read(emulatorControllerProvider).fddMedia[0], 'GAME.D88');
    expect(session.insertCalls, hasLength(1));

    // 挿入済みでも「排出」「挿入…」の両方が有効のまま
    // （入れ替えのため。menu_catalog.dartのenabled条件）。
    await openFd1Menu(tester);
    expect(
      tester
          .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, '排出'))
          .onPressed,
      isNotNull,
    );
    expect(
      tester
          .widget<MenuItemButton>(find.widgetWithText(MenuItemButton, '挿入…'))
          .onPressed,
      isNotNull,
    );
    container.dispose();
  });

  testWidgets('FDD-01 挿入済みドライブへ再度挿入すると入れ替わる', (tester) async {
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/GAME.D88',
      displayName: 'GAME.D88',
    );
    final container = await wrap(tester);
    await tester.pumpAndSettle();

    await openFd1Menu(tester);
    await tester.tap(find.text('挿入…'));
    await tester.pumpAndSettle();

    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/OTHER.D88',
      displayName: 'OTHER.D88',
    );
    await openFd1Menu(tester);
    await tester.tap(find.text('挿入…'));
    await tester.pumpAndSettle();

    expect(
      container.read(emulatorControllerProvider).fddMedia[0],
      'OTHER.D88',
    );
    expect(session.insertCalls, hasLength(2));
    expect(session.ejectCalls, [0]);
    expect(cacheWorkspace.handle.exportCalls, [
      ('fd0-GAME.D88', '/Volumes/USB/GAME.D88'),
    ]);
    container.dispose();
  });

  testWidgets('FDD-01 Diskメニューから排出すると原本へ書き戻し、未挿入表示に戻る', (tester) async {
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/GAME.D88',
      displayName: 'GAME.D88',
    );
    final container = await wrap(tester);
    await tester.pumpAndSettle();

    await openFd1Menu(tester);
    await tester.tap(find.text('挿入…'));
    await tester.pumpAndSettle();

    await openFd1Menu(tester);
    await tester.tap(find.text('排出'));
    await tester.pumpAndSettle();

    expect(container.read(emulatorControllerProvider).fddMedia[0], isNull);
    expect(session.ejectCalls, [0]);
    expect(cacheWorkspace.handle.exportCalls, [
      ('fd0-GAME.D88', '/Volumes/USB/GAME.D88'),
    ]);
    container.dispose();
  });
}
