import 'package:bubifm77av40ex/app/menu/app_menu_bar.dart';
import 'package:bubifm77av40ex/app/menu/menu_command.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// [AppMenuBar.onMenuOpenChanged]（メニュー表示中の一時停止）の通知。
void main() {
  Widget buildBar(List<bool> changes, {void Function()? onSelected}) {
    return MaterialApp(
      home: AppMenuBar(
        onMenuOpenChanged: changes.add,
        groups: [
          MenuGroup(
            id: MenuGroupId.control,
            label: 'Control',
            entries: [
              MenuAction(
                'control.reset',
                label: 'Reset',
                enabled: true,
                onSelected: onSelected ?? () {},
              ),
            ],
          ),
          const MenuGroup(
            id: MenuGroupId.disk,
            label: 'Disk',
            entries: [
              MenuAction(
                'disk.none',
                label: 'None',
                enabled: true,
                onSelected: _noop,
              ),
            ],
          ),
        ],
        child: const SizedBox.expand(),
      ),
    );
  }

  testWidgets('メニューを開くとtrue、項目を選んで閉じるとfalseを通知する', (tester) async {
    final changes = <bool>[];
    var selected = false;
    await tester.pumpWidget(
      buildBar(changes, onSelected: () => selected = true),
    );

    await tester.tap(find.text('Control'));
    await tester.pumpAndSettle();
    expect(changes, [true]);

    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    expect(changes, [true, false]);
  });

  testWidgets('開いたまま隣のメニューへ移ってもfalseを挟まない', (tester) async {
    final changes = <bool>[];
    await tester.pumpWidget(buildBar(changes));

    await tester.tap(find.text('Control'));
    await tester.pumpAndSettle();
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: tester.getCenter(find.text('Control')));
    await gesture.moveTo(tester.getCenter(find.text('Disk')));
    await tester.pumpAndSettle();
    expect(find.text('None'), findsOneWidget);
    expect(changes, [true]);

    await tester.tapAt(const Offset(400, 400));
    await tester.pumpAndSettle();
    expect(changes, [true, false]);
    await gesture.removePointer();
  });
}

void _noop() {}
