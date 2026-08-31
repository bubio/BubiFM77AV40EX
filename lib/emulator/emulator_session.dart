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

  /// 観測値を読み出す。
  EmulatorStats readStats();

  /// セッションを破棄する。以後この実体は使えない。冪等。
  Future<void> dispose();
}
