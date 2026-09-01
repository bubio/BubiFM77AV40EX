import 'emulator_event.dart';
import 'emulator_stats.dart';
import 'session_state.dart';

/// エミュレーターコアとの境界（design.md 4.1）。
///
/// 実装は `lib/platform/core_ffi/` にあり、`app` が注入する。
/// `features` はこの抽象だけに依存し、FFIやプラグインを直接触らない。
abstract class EmulatorSession {
  /// 直近のライフサイクル状態。
  SessionState get state;

  /// 低頻度イベントの通知。購読者がいなくてもコアは進み続ける。
  Stream<EmulatorEvent> get events;

  /// Core thread を起動する。
  ///
  /// すでに起動していれば [EmulatorException] を `invalidState` で投げる。
  /// 起動要求の受理と実際の初期化成功は別で、失敗は
  /// [LifecycleChanged] の [SessionState.failed] と
  /// [EmulatorErrorOccurred] で通知する。
  Future<void> start();

  /// Core thread を停止して join する。冪等。
  Future<void> stop();

  /// リセットを投入し、コマンドの連番を返す。
  ///
  /// 完了は同じIDの [CommandCompleted] で通知する。
  Future<int> reset(ResetKind kind);

  /// ブートモードを設定し、コマンドの連番を返す。
  ///
  /// コアはリセット時にこの値を読むため、反映されるのは次の
  /// [reset] または再起動からになる（SYS-04）。
  Future<int> setBootMode(BootMode mode);

  /// キーを押す。[vkCode] は win32 の仮想キーコード（INP-01）。
  ///
  /// リピートの抑止と重複押下の除去は呼び出し側（Controller）の責務で、
  /// ここは受け取った1回をそのままコアへ渡す。
  Future<void> keyDown(int vkCode);

  /// キーを離す。[vkCode] は win32 の仮想キーコード（INP-01）。
  Future<void> keyUp(int vkCode);

  /// 観測値を読み出す。
  EmulatorStats readStats();

  /// 画面を受け取る Texture を用意し、そのIDを返す。
  ///
  /// 呼ぶたびに新しいIDを作るのではなく、すでにあればそれを返す。
  /// 解除は [detachVideoTexture] で行い、[dispose] は先に解除する。
  /// 順序を守らないと描画スレッドが解放済みのセッションを読む
  /// （design.md 5.1 の終了順序）。
  Future<int> attachVideoTexture();

  /// Texture を解除する。冪等。
  Future<void> detachVideoTexture();

  /// セッションを破棄する。以後この実体は使えない。冪等。
  Future<void> dispose();
}
