import 'package:gamepads/gamepads.dart';

export 'package:gamepads/gamepads.dart' show GamepadAxis, GamepadButton;

/// 接続中の物理ジョイスティック/ゲームパッド1台の情報（M3 INP-04）。
typedef JoystickInfo = ({String id, String name});

/// `gamepads`パッケージの正規化イベントのうち、この機能が使う分だけを
/// 抜き出した形（`button`か`axis`のどちらか一方だけが非null）。
typedef JoystickInputEvent = ({
  String gamepadId,
  GamepadButton? button,
  GamepadAxis? axis,
  double value,
});

/// 物理ジョイスティック入力の境界（design.md 3.1「featureはplatform実装を
/// 知らない」と同じ考え方）。
///
/// `gamepads`パッケージへの直接依存をここへ閉じ込め、テストでは
/// プラグインの実チャンネルを叩かないFakeへ差し替える。
abstract class JoystickSource {
  /// 現在接続中のコントローラー一覧。
  Future<List<JoystickInfo>> list();

  /// 全コントローラーの入力イベント（`gamepadId`で対象を判別する）。
  Stream<JoystickInputEvent> get events;
}

/// `gamepads`パッケージへ委譲する実装。
class GamepadsJoystickSource implements JoystickSource {
  const GamepadsJoystickSource();

  @override
  Future<List<JoystickInfo>> list() async {
    final controllers = await Gamepads.list();
    try {
      return [
        for (final controller in controllers)
          (id: controller.id, name: controller.name),
      ];
    } finally {
      // GamepadControllerはコンストラクタで自前のイベント購読を始める
      // （`gamepads_platform_interface`のドキュメント）。id/nameだけが
      // 目的で、入力自体は`events`（Gamepads.normalizedEvents）で別途
      // 購読するため、ここで確実にdisposeして二重購読・リークを避ける。
      for (final controller in controllers) {
        await controller.dispose();
      }
    }
  }

  @override
  Stream<JoystickInputEvent> get events => Gamepads.normalizedEvents.map(
    (event) => (
      gamepadId: event.gamepadId,
      button: event.button,
      axis: event.axis,
      value: event.value,
    ),
  );
}
