import 'package:bubifm77av40ex/app/pause_on_popup_observer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [PauseOnPopupObserver]（ダイアログ・アラート表示中の一時停止）。
void main() {
  late int requests;
  late PauseOnPopupObserver observer;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() {
    requests = 0;
    observer = PauseOnPopupObserver(
      acquirePause: () {
        requests++;
        var released = false;
        return () {
          if (!released) {
            released = true;
            requests--;
          }
        };
      },
    );
    navigatorKey = GlobalKey<NavigatorState>();
  });

  Widget buildApp() => MaterialApp(
    navigatorKey: navigatorKey,
    navigatorObservers: [observer],
    home: const Scaffold(),
  );

  Future<void> openDialog(WidgetTester tester, String text) async {
    showDialog<void>(
      context: navigatorKey.currentContext!,
      builder: (context) => AlertDialog(content: Text(text)),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('ダイアログの表示中だけ一時停止を求める', (tester) async {
    await tester.pumpWidget(buildApp());
    expect(requests, 0);

    await openDialog(tester, 'first');
    expect(requests, 1);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(requests, 0);
  });

  testWidgets('ダイアログを重ねても最後の1つが閉じるまで取り下げない', (tester) async {
    await tester.pumpWidget(buildApp());

    await openDialog(tester, 'first');
    await openDialog(tester, 'second');
    expect(requests, 2);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(requests, 1);

    navigatorKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(requests, 0);
  });

  testWidgets('通常の画面遷移では一時停止しない', (tester) async {
    await tester.pumpWidget(buildApp());

    navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold()),
    );
    await tester.pumpAndSettle();
    expect(requests, 0);
  });
}
