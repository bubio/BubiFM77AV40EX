import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:bubifm77av40ex/app/l10n/generated/app_localizations_en.dart';
import 'package:bubifm77av40ex/features/session/emulator_state.dart';
import 'package:bubifm77av40ex/features/session/widgets/status_bar.dart';

void main() {
  group('shortenCmtMessage', () {
    test('テープ先頭での停止を0 %で表す', () {
      expect(shortenCmtMessage('Stop (Beginning-of-Tape)'), 'Stop (0 %)');
    });

    test('テープ終端での停止を100 %で表す', () {
      expect(shortenCmtMessage('Stop (End-of-Tape)'), 'Stop (100 %)');
    });

    test('それ以外の状態文字列はそのまま返す', () {
      expect(shortenCmtMessage('Stop (50 %)'), 'Stop (50 %)');
      expect(shortenCmtMessage('Play (3 %)'), 'Play (3 %)');
      expect(shortenCmtMessage('Stop'), 'Stop');
    });
  });

  group('GrowOnlyText', () {
    Widget host(String text) => Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: GrowOnlyText(text)),
    );

    testWidgets('短い文字列に変わっても最大幅を保つ', (tester) async {
      await tester.pumpWidget(host('Core 9 fps'));
      final narrow = tester.getSize(find.byType(GrowOnlyText)).width;

      await tester.pumpWidget(host('Core 120 fps'));
      final wide = tester.getSize(find.byType(GrowOnlyText)).width;
      expect(wide, greaterThan(narrow));

      await tester.pumpWidget(host('Core 60 fps'));
      expect(tester.getSize(find.byType(GrowOnlyText)).width, wide);
      expect(find.text('Core 60 fps'), findsOneWidget);
    });
  });

  group('StatusBar', () {
    Future<void> pumpStatusBar(
      WidgetTester tester, {
      double masterVolume = 0.5,
      ValueChanged<double>? onMasterVolumeChanged,
    }) async {
      tester.view.physicalSize = const Size(1200, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: StatusBar(
                state: const EmulatorViewState(),
                l10n: AppLocalizationsEn(),
                masterVolume: masterVolume,
                onMasterVolumeChanged: onMasterVolumeChanged ?? (_) {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('音量スライダーの操作でマスター音量の変更を通知する', (tester) async {
      double? changed;
      await pumpStatusBar(
        tester,
        masterVolume: 0.5,
        onMasterVolumeChanged: (value) => changed = value,
      );
      expect(find.text('50%'), findsOneWidget);

      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('statusMasterVolumeSlider'))) +
            const Offset(30, 0),
      );
      expect(changed, isNotNull);
      expect(changed!, greaterThan(0.5));
    });
  });
}
