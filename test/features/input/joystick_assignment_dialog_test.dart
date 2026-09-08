import 'package:bubi_fm77av40ex/app/l10n/generated/app_localizations.dart';
import 'package:bubi_fm77av40ex/features/input/joystick_assignment_controller.dart';
import 'package:bubi_fm77av40ex/features/input/joystick_assignment_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// ジョイスティック割当ダイアログ（M3 INP-04）。
///
/// 接続一覧の表示とドロップダウンでの割当変更を確認する。
void main() {
  late FakeJoystickSource source;
  late ProviderContainer container;

  setUp(() {
    source = FakeJoystickSource();
    container = ProviderContainer(
      overrides: [
        joystickAssignmentControllerProvider.overrideWith(
          () => JoystickAssignmentController(source: source),
        ),
      ],
    );
  });

  Future<void> openDialog(WidgetTester tester) async {
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
                key: const Key('openJoystickAssignmentDialog'),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => const JoystickAssignmentDialog(),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('openJoystickAssignmentDialog')));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('接続中のコントローラーがドロップダウンへ並ぶ', (tester) async {
    source.connected = [
      (id: 'pad-1', name: 'Pad 1'),
      (id: 'pad-2', name: 'Pad 2'),
    ];

    await openDialog(tester);
    await tester.tap(find.byKey(const Key('joystickAssignmentDialogSlot0')));
    await tester.pumpAndSettle();

    expect(find.text('Pad 1'), findsOneWidget);
    expect(find.text('Pad 2'), findsOneWidget);
    container.dispose();
  });

  testWidgets('スロットのドロップダウンを選ぶとassignが呼ばれる', (tester) async {
    source.connected = [(id: 'pad-1', name: 'Pad 1')];
    await openDialog(tester);

    await tester.tap(find.byKey(const Key('joystickAssignmentDialogSlot0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pad 1').last);
    await tester.pump();

    expect(
      container.read(joystickAssignmentControllerProvider).assignments[0],
      'pad-1',
    );
    container.dispose();
  });

  testWidgets('Closeボタンでダイアログを閉じる', (tester) async {
    await openDialog(tester);

    await tester.tap(find.byKey(const Key('joystickAssignmentDialogClose')));
    await tester.pump();

    expect(find.byType(JoystickAssignmentDialog), findsNothing);
    container.dispose();
  });
}
