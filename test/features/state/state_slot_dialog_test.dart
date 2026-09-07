import 'dart:convert';
import 'dart:io';

import 'package:bubi_fm77av40ex/app/l10n/generated/app_localizations.dart';
import 'package:bubi_fm77av40ex/emulator/session_state.dart';
import 'package:bubi_fm77av40ex/features/display/screenshot_service.dart';
import 'package:bubi_fm77av40ex/features/session/emulator_controller.dart';
import 'package:bubi_fm77av40ex/features/session/session_providers.dart';
import 'package:bubi_fm77av40ex/features/state/state_slot_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../session/fakes.dart';

/// 状態スロットのグリッドダイアログ（STA-01/STA-02）。
///
/// `~/dev/_Emu/Bubilator88`の`SaveStateSheetView`を参考にしたグリッド、
/// 空スロットのプレースホルダ、Loadモードでの無効化、セルタップでの
/// 即時確定・ダイアログクローズを確認する。
void main() {
  late Directory tempDir;
  late FakeAppDataPaths appDataPaths;
  late FakeEmulatorSession session;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('state_slot_dialog_test');
    appDataPaths = FakeAppDataPaths()..statesPath = tempDir.path;
    session = FakeEmulatorSession();
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // `StateSlotDialog`は`listStateSlots()`/`saveState()`/`loadState()`で
  // 実dart:ioを行う。`testWidgets`のテスト本体は`AutomatedTestWidgetsFlutterBinding`
  // の中で実行され、`tester.pump()`だけでは実I/Oのコールバックが進まない
  // （real event loopへ戻らない）ため`pumpAndSettle`は使えない
  // （`CircularProgressIndicator`のような常時アニメーションが無くても
  // Futureそのものが解決しない）。`runAsync`のコールバック内でtap/pumpまで
  // 行うことで、実I/Oを実イベントループ上で完了させてから描画を反映する。
  Future<void> tapAndWaitRealIo(WidgetTester tester, String key) async {
    await tester.runAsync(() async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pump();
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  Future<ProviderContainer> wrap(
    WidgetTester tester,
    StateSlotDialogMode mode,
  ) async {
    final container = ProviderContainer(
      overrides: [
        emulatorControllerProvider.overrideWith(
          () => EmulatorController(
            appDataPaths: appDataPaths,
            externalFileAccess: FakeExternalFileAccess(),
            cacheWorkspace: FakeCacheWorkspace(),
            preferences: FakePreferencesStore(),
            createSession: ({
              required String homeDir,
              String? romDir,
              BootMode bootMode = BootMode.basic,
            }) => session,
          ),
        ),
        screenshotServiceProvider.overrideWithValue(
          ScreenshotService(appDataPaths: appDataPaths),
        ),
      ],
    );
    // `addTearDown`ではなく各テスト末尾で明示的に`dispose()`する
    // （`_statsTimer`の解除が`AutomatedTestWidgetsFlutterBinding`の
    // pending-timer検査より後に走ると失敗するため、他のwidget test
    // と同じくテスト本体の中で同期的に片付ける）。
    await container.read(emulatorControllerProvider.notifier).launch();

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
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
                key: const Key('openStateSlotDialog'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => StateSlotDialog(mode: mode),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tapAndWaitRealIo(tester, 'openStateSlotDialog');
    return container;
  }

  void writeSlot(int slot, {List<String> diskNames = const []}) {
    final dir = Directory('${tempDir.path}/slot-$slot')
      ..createSync(recursive: true);
    File('${dir.path}/metadata.json').writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'createdAt': DateTime(2026, 1, 2, 3, 4).toIso8601String(),
        'diskNames': diskNames,
      }),
    );
  }

  testWidgets('スロット0〜9のグリッドを表示する', (tester) async {
    final container = await wrap(tester, StateSlotDialogMode.save);

    for (var slot = 0; slot < EmulatorController.stateSlotCount; slot++) {
      expect(find.byKey(Key('stateSlotCell_$slot')), findsOneWidget);
    }
    container.dispose();
  });

  testWidgets('Loadモードで空スロットは無効化されタップしても何もしない', (tester) async {
    final container = await wrap(tester, StateSlotDialogMode.load);

    await tapAndWaitRealIo(tester, 'stateSlotCell_0');

    expect(session.loadStateCalls, isEmpty);
    // ダイアログは閉じない。
    expect(find.byType(StateSlotDialog), findsOneWidget);
    container.dispose();
  });

  testWidgets('Loadモードでデータのあるスロットをタップすると読み込んでダイアログを閉じる', (tester) async {
    writeSlot(4, diskNames: ['GAME.D88']);

    final container = await wrap(tester, StateSlotDialogMode.load);
    await tapAndWaitRealIo(tester, 'stateSlotCell_4');

    expect(session.loadStateCalls, ['${tempDir.path}/slot-4/state.bin']);
    expect(find.byType(StateSlotDialog), findsNothing);
    container.dispose();
  });

  testWidgets('Saveモードでセルをタップすると保存してダイアログを閉じる', (tester) async {
    final container = await wrap(tester, StateSlotDialogMode.save);

    await tapAndWaitRealIo(tester, 'stateSlotCell_2');

    expect(session.saveStateCalls, ['${tempDir.path}/slot-2/state.bin']);
    expect(find.byType(StateSlotDialog), findsNothing);
    container.dispose();
  });

  testWidgets('Cancelボタンは何もせずダイアログを閉じる', (tester) async {
    final container = await wrap(tester, StateSlotDialogMode.save);

    await tapAndWaitRealIo(tester, 'stateSlotDialogCancel');

    expect(session.saveStateCalls, isEmpty);
    expect(session.loadStateCalls, isEmpty);
    expect(find.byType(StateSlotDialog), findsNothing);
    container.dispose();
  });
}
