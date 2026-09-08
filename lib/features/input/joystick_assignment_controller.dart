import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../emulator/joystick_bit.dart';
import 'joystick_source.dart';

/// ジョイスティック割当の状態（M3 INP-04）。
///
/// `assignments`はスロット（0=JS1、1=JS2）→コントローラーID（未割当はnull）。
/// `bits`はスロットごとの現在の入力状態（[JoystickBit]）。`connected`は
/// 接続中のコントローラー一覧で、ダイアログを開いている間だけ
/// [JoystickAssignmentController.refreshConnected]で更新する。
///
/// 再起動をまたいで永続化しない。コントローラーIDは再接続のたびに
/// 変わりうる上、同一機種2台を区別する安定キーが無いため（design.md
/// 「ジョイスティック割当（M3、INP-04）の実装方式」の既知の制限）。
typedef JoystickAssignmentState = ({
  Map<int, String?> assignments,
  Map<int, int> bits,
  List<JoystickInfo> connected,
});

const _initialJoystickAssignmentState = (
  assignments: {0: null, 1: null},
  bits: {0: 0, 1: 0},
  connected: <JoystickInfo>[],
);

/// 1台のコントローラーの生の押下・軸状態（内部専用）。
///
/// 方向はD-padと左スティックのOR合成（design.md）。スティックは
/// ヒステリシスdeadzone（検出0.3・解除0.2）でチャタリングを防ぐ。
class _RawGamepadState {
  bool dpadUp = false;
  bool dpadDown = false;
  bool dpadLeft = false;
  bool dpadRight = false;
  bool buttonA = false;
  bool buttonB = false;
  bool stickUp = false;
  bool stickDown = false;
  bool stickLeft = false;
  bool stickRight = false;

  static const _detect = 0.3;
  static const _release = 0.2;

  bool get up => dpadUp || stickUp;
  bool get down => dpadDown || stickDown;
  bool get left => dpadLeft || stickLeft;
  bool get right => dpadRight || stickRight;

  void apply(JoystickInputEvent event) {
    final button = event.button;
    if (button != null) {
      final pressed = event.value != 0;
      switch (button) {
        case GamepadButton.dpadUp:
          dpadUp = pressed;
        case GamepadButton.dpadDown:
          dpadDown = pressed;
        case GamepadButton.dpadLeft:
          dpadLeft = pressed;
        case GamepadButton.dpadRight:
          dpadRight = pressed;
        case GamepadButton.a:
          buttonA = pressed;
        case GamepadButton.b:
          buttonB = pressed;
        default:
          break;
      }
      return;
    }
    switch (event.axis) {
      case GamepadAxis.leftStickX:
        stickLeft = _latch(stickLeft, -event.value);
        stickRight = _latch(stickRight, event.value);
      case GamepadAxis.leftStickY:
        stickUp = _latch(stickUp, event.value);
        stickDown = _latch(stickDown, -event.value);
      default:
        break;
    }
  }

  static bool _latch(bool current, double value) {
    return value > (current ? _release : _detect);
  }

  int toBits() {
    var bits = 0;
    if (up) bits |= JoystickBit.up;
    if (down) bits |= JoystickBit.down;
    if (left) bits |= JoystickBit.left;
    if (right) bits |= JoystickBit.right;
    if (buttonA) bits |= JoystickBit.button1;
    if (buttonB) bits |= JoystickBit.button2;
    return bits;
  }
}

/// ジョイスティック割当を管理する（M3 INP-04）。
///
/// 入力イベント自体の購読はアプリの生存期間中つねに行い、[bits]の変化を
/// state経由で公開する。実際にコアへ送るのは`app`層が
/// `ref.listen`で拾って`EmulatorController.setJoystickState`を呼ぶ
/// （design.md 3.1、他のcontroller間連携と同じ`_HomeState.build()`の
/// `ref.listen`パターン）。
class JoystickAssignmentController extends Notifier<JoystickAssignmentState> {
  JoystickAssignmentController({required this.source});

  final JoystickSource source;

  StreamSubscription<JoystickInputEvent>? _subscription;
  final Map<String, _RawGamepadState> _raw = {};

  @override
  JoystickAssignmentState build() {
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
    });
    _subscription = source.events.listen(_handleEvent);
    return _initialJoystickAssignmentState;
  }

  /// 接続一覧を更新する。ダイアログを開いている間だけ呼ぶ想定
  /// （接続/切断の専用通知が`gamepads`パッケージに無いため、design.md
  /// 「ジョイスティック割当（M3、INP-04）の実装方式」のとおりポーリング
  /// する）。切断されたコントローラーが割り当たっていたスロットは
  /// 未割当へ戻し、押しっぱなし状態を残さないようビットも0へ戻す。
  Future<void> refreshConnected() async {
    final connected = await source.list();
    final connectedIds = connected.map((info) => info.id).toSet();

    final assignments = {...state.assignments};
    final bits = {...state.bits};
    for (final slot in state.assignments.keys) {
      final gamepadId = assignments[slot];
      if (gamepadId != null && !connectedIds.contains(gamepadId)) {
        assignments[slot] = null;
        bits[slot] = 0;
      }
    }
    state = (assignments: assignments, bits: bits, connected: connected);
  }

  /// スロット[slot]（0=JS1、1=JS2）へ[gamepadId]を割り当てる。
  /// nullを渡すと未割当に戻す。
  void assign(int slot, String? gamepadId) {
    final assignments = {...state.assignments};
    final bits = {...state.bits};
    if (gamepadId != null) {
      // 同じコントローラーを2つのスロットへ重複させない。
      for (final other in assignments.keys) {
        if (other != slot && assignments[other] == gamepadId) {
          assignments[other] = null;
          bits[other] = 0;
        }
      }
    }
    assignments[slot] = gamepadId;
    bits[slot] = gamepadId == null ? 0 : (_raw[gamepadId]?.toBits() ?? 0);
    state = (assignments: assignments, bits: bits, connected: state.connected);
  }

  void _handleEvent(JoystickInputEvent event) {
    final raw = _raw.putIfAbsent(event.gamepadId, _RawGamepadState.new);
    raw.apply(event);

    int? slot;
    for (final entry in state.assignments.entries) {
      if (entry.value == event.gamepadId) {
        slot = entry.key;
        break;
      }
    }
    if (slot == null) {
      return;
    }
    final bits = raw.toBits();
    if (bits == state.bits[slot]) {
      return;
    }
    state = (
      assignments: state.assignments,
      bits: {...state.bits, slot: bits},
      connected: state.connected,
    );
  }
}

final joystickAssignmentControllerProvider =
    NotifierProvider<JoystickAssignmentController, JoystickAssignmentState>(
      () => throw UnimplementedError('appがoverrideWithで組み立てる'),
    );
