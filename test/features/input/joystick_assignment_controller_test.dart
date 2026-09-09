import 'package:bubifm77av40ex/emulator/joystick_bit.dart';
import 'package:bubifm77av40ex/features/input/joystick_assignment_controller.dart';
import 'package:bubifm77av40ex/features/input/joystick_source.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

JoystickInputEvent _button(String id, GamepadButton button, bool pressed) =>
    (gamepadId: id, button: button, axis: null, value: pressed ? 1.0 : 0.0);

JoystickInputEvent _axis(String id, GamepadAxis axis, double value) =>
    (gamepadId: id, button: null, axis: axis, value: value);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeJoystickSource source;
  late ProviderContainer container;
  late NotifierProvider<JoystickAssignmentController, JoystickAssignmentState>
  provider;

  setUp(() {
    source = FakeJoystickSource();
    provider =
        NotifierProvider<JoystickAssignmentController, JoystickAssignmentState>(
          () => JoystickAssignmentController(source: source),
        );
    container = ProviderContainer();
    addTearDown(container.dispose);
    addTearDown(source.dispose);
  });

  JoystickAssignmentController controller() =>
      container.read(provider.notifier);
  JoystickAssignmentState state() => container.read(provider);

  test('INP-04 初期状態は両スロット未割当・未接続', () {
    expect(state().assignments, {0: null, 1: null});
    expect(state().bits, {0: 0, 1: 0});
    expect(state().connected, isEmpty);
  });

  test('INP-04 refreshConnectedは接続一覧を反映する', () async {
    source.connected = [(id: 'pad-1', name: 'Pad 1')];

    await controller().refreshConnected();

    expect(state().connected, [(id: 'pad-1', name: 'Pad 1')]);
  });

  test('INP-04 assignは指定スロットへ割り当てる', () {
    controller().assign(0, 'pad-1');

    expect(state().assignments, {0: 'pad-1', 1: null});
  });

  test('INP-04 同じコントローラーを別スロットへ割り当てると元のスロットは解除される', () {
    controller().assign(0, 'pad-1');
    controller().assign(1, 'pad-1');

    expect(state().assignments, {0: null, 1: 'pad-1'});
  });

  test('INP-04 割り当てたスロットの方向ボタンはJoystickBit.upへ反映される', () async {
    controller().assign(0, 'pad-1');
    source.emit(_button('pad-1', GamepadButton.dpadUp, true));
    await _flush();

    expect(state().bits[0], JoystickBit.up);
  });

  test('INP-04 未割当のコントローラーからのイベントは無視される', () async {
    source.emit(_button('pad-1', GamepadButton.dpadUp, true));
    await _flush();

    expect(state().bits, {0: 0, 1: 0});
  });

  test('INP-04 AボタンとBボタンはButton1/Button2へ対応する', () async {
    controller().assign(0, 'pad-1');
    source.emit(_button('pad-1', GamepadButton.a, true));
    await _flush();
    expect(state().bits[0], JoystickBit.button1);

    source.emit(_button('pad-1', GamepadButton.b, true));
    await _flush();
    expect(state().bits[0], JoystickBit.button1 | JoystickBit.button2);
  });

  test('INP-04 左スティックはヒステリシスdeadzoneで方向ビットへ変換される', () async {
    controller().assign(0, 'pad-1');

    // 検出しきい値（0.3）未満は反応しない。
    source.emit(_axis('pad-1', GamepadAxis.leftStickX, 0.25));
    await _flush();
    expect(state().bits[0], 0);

    // 検出しきい値を超えると立つ。
    source.emit(_axis('pad-1', GamepadAxis.leftStickX, 0.35));
    await _flush();
    expect(state().bits[0], JoystickBit.right);

    // 解除しきい値（0.2）まで戻っても保持される（ヒステリシス）。
    source.emit(_axis('pad-1', GamepadAxis.leftStickX, 0.25));
    await _flush();
    expect(state().bits[0], JoystickBit.right);

    // 解除しきい値を下回ると落ちる。
    source.emit(_axis('pad-1', GamepadAxis.leftStickX, 0.1));
    await _flush();
    expect(state().bits[0], 0);
  });

  test('INP-04 refreshConnectedは切断されたコントローラーの割当とビットを解除する', () async {
    controller().assign(0, 'pad-1');
    source.emit(_button('pad-1', GamepadButton.a, true));
    await _flush();
    expect(state().bits[0], JoystickBit.button1);

    source.connected = [];
    await controller().refreshConnected();

    expect(state().assignments[0], isNull);
    expect(state().bits[0], 0);
  });

  test('INP-04 未割当へ戻すとビットは0へ戻る', () async {
    controller().assign(0, 'pad-1');
    source.emit(_button('pad-1', GamepadButton.a, true));
    await _flush();
    expect(state().bits[0], JoystickBit.button1);

    controller().assign(0, null);

    expect(state().assignments[0], isNull);
    expect(state().bits[0], 0);
  });
}
