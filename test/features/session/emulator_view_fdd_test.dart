import 'package:bubi_fm77av40ex/app/l10n/generated/app_localizations.dart';
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
  Widget build(BuildContext context) => const EmulatorView();
}

/// FDD-01の挿入・排出ボタン（design.md 16.1）の画面からの操作を確かめる。
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

  // macOSのウィンドウはデフォルトの試験画面（800×600）より広いのが通常。
  // 下部ツールバーはその幅を前提にしているため、試験だけ画面を広げる。
  Future<void> useDesktopSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

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

  testWidgets('FDD-01 挿入すると媒体名を出し、ボタンが排出に変わる', (tester) async {
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/GAME.D88',
      displayName: 'GAME.D88',
    );

    await useDesktopSurface(tester);
    final container = await wrap(tester);
    await tester.pumpAndSettle();
    expect(find.text('FD1: 未挿入'), findsOneWidget);

    await tester.tap(find.byKey(const Key('fdd0Action')));
    await tester.pumpAndSettle();

    expect(find.text('FD1: GAME.D88'), findsOneWidget);
    expect(find.text('排出'), findsOneWidget);
    expect(session.insertCalls, hasLength(1));
    container.dispose();
  });

  testWidgets('FDD-01 排出すると原本へ書き戻し、未挿入表示に戻る', (tester) async {
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/GAME.D88',
      displayName: 'GAME.D88',
    );
    await useDesktopSurface(tester);
    final container = await wrap(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('fdd0Action')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('fdd0Action')));
    await tester.pumpAndSettle();

    expect(find.text('FD1: 未挿入'), findsOneWidget);
    expect(session.ejectCalls, [0]);
    expect(cacheWorkspace.handle.exportCalls, [
      ('fd0-GAME.D88', '/Volumes/USB/GAME.D88'),
    ]);
    container.dispose();
  });
}
