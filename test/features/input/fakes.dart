import 'dart:async';

import 'package:bubi_fm77av40ex/features/input/joystick_source.dart';

/// [JoystickSource]のFake。実チャンネルを叩かずイベント・一覧を注入できる。
class FakeJoystickSource implements JoystickSource {
  List<JoystickInfo> connected = [];
  final _controller = StreamController<JoystickInputEvent>.broadcast();

  @override
  Future<List<JoystickInfo>> list() async => connected;

  @override
  Stream<JoystickInputEvent> get events => _controller.stream;

  void emit(JoystickInputEvent event) => _controller.add(event);

  Future<void> dispose() => _controller.close();
}
