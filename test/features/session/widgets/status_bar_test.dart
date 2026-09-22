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

  group('parseCmtMessage', () {
    test('走行状態と走行位置に分ける', () {
      expect(parseCmtMessage('Play (3 %)'), (
        transport: CmtTransport.play,
        percent: 3,
      ));
      expect(parseCmtMessage('Fast Forward (40 %)'), (
        transport: CmtTransport.fastForward,
        percent: 40,
      ));
      expect(parseCmtMessage('Fast Rewind (7 %)'), (
        transport: CmtTransport.fastRewind,
        percent: 7,
      ));
    });

    test('位置のない状態は位置をnullにする', () {
      expect(parseCmtMessage('Stop'), (
        transport: CmtTransport.stop,
        percent: null,
      ));
      expect(parseCmtMessage('Record'), (
        transport: CmtTransport.record,
        percent: null,
      ));
    });

    test('テープ端の停止は0 %/100 %として解釈する', () {
      expect(parseCmtMessage('Stop (End-of-Tape)'), (
        transport: CmtTransport.stop,
        percent: 100,
      ));
    });

    test('未知の文字列はnullを返す', () {
      expect(parseCmtMessage('Eject'), isNull);
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
      EmulatorViewState state = const EmulatorViewState(),
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
                state: state,
                l10n: AppLocalizationsEn(),
                masterVolume: masterVolume,
                onMasterVolumeChanged: onMasterVolumeChanged ?? (_) {},
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('CMT表示が短くてもFPSをステータスバーの右端へ寄せる', (tester) async {
      await pumpStatusBar(tester);
      final bar = tester.getRect(find.byType(StatusBar));
      final coreFps = tester.getRect(find.text('Core 0 fps'));
      // 右端の余白はContainerのpadding（8論理px）だけになる。
      expect(coreFps.right, closeTo(bar.right - 8, 0.5));
    });

    testWidgets('CMTの走行状態をアイコンと位置の数字で表示する', (tester) async {
      await pumpStatusBar(
        tester,
        state: const EmulatorViewState(
          cmtPlaying: true,
          cmtMessage: 'Play (3 %)',
        ),
      );
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
      expect(find.text('3 %'), findsOneWidget);
      expect(find.text('CMT : Play (3 %)'), findsNothing);
      expect(find.bySemanticsLabel('CMT : Play (3 %)'), findsOneWidget);
    });

    testWidgets('CMTの走行位置は桁数によらず3桁分の幅を保つ', (tester) async {
      await pumpStatusBar(
        tester,
        state: const EmulatorViewState(cmtMessage: 'Play (3 %)'),
      );
      final oneDigit = tester.getRect(find.text('3 %')).right;

      await pumpStatusBar(
        tester,
        state: const EmulatorViewState(cmtMessage: 'Play (100 %)'),
      );
      expect(tester.getRect(find.text('100 %').last).right, oneDigit);
    });

    testWidgets('解釈できないCMT状態文字列は全文を表示する', (tester) async {
      await pumpStatusBar(
        tester,
        state: const EmulatorViewState(cmtMessage: 'Eject'),
      );
      expect(find.text('CMT : Eject'), findsOneWidget);
    });

    testWidgets('音量スライダーの操作でマスター音量の変更を通知する', (tester) async {
      double? changed;
      await pumpStatusBar(
        tester,
        masterVolume: 0.5,
        onMasterVolumeChanged: (value) => changed = value,
      );
      expect(find.text('50%'), findsNothing);

      await tester.tapAt(
        tester.getCenter(find.byKey(const Key('statusMasterVolumeSlider'))) +
            const Offset(30, 0),
      );
      expect(changed, isNotNull);
      expect(changed!, greaterThan(0.5));
    });
  });
}
