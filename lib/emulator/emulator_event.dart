import 'emulator_error.dart';
import 'led_state.dart';
import 'session_state.dart';

/// コアから届く低頻度イベント（design.md 4.3）。
///
/// PCMサンプル、画素列、キーイベント列はここを通さない。
sealed class EmulatorEvent {
  const EmulatorEvent();
}

/// ライフサイクル状態が変わった。
class LifecycleChanged extends EmulatorEvent {
  const LifecycleChanged(this.state);

  final SessionState state;
}

/// 投入したコマンドが完了した。[commandId] は投入時に返った連番。
class CommandCompleted extends EmulatorEvent {
  const CommandCompleted(this.commandId, {this.error});

  final int commandId;

  /// 成功なら null。
  final EmulatorErrorCode? error;

  bool get succeeded => error == null;
}

/// コマンドに紐づかないエラーが起きた。
class EmulatorErrorOccurred extends EmulatorEvent {
  const EmulatorErrorOccurred(this.code);

  final EmulatorErrorCode code;
}

/// 画面の論理解像度が変わった（VID-01）。
///
/// コアは320×200、640×200、640×400のいずれかを返す。表示側は
/// これで縦横比と拡大率を決める（VID-02）。
class ScreenModeChanged extends EmulatorEvent {
  const ScreenModeChanged(this.width, this.height);

  final int width;
  final int height;

  @override
  bool operator ==(Object other) =>
      other is ScreenModeChanged &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(width, height);
}

/// INS、KANA、CAPSのLEDが変わった（INP-02）。
class LedStateChanged extends EmulatorEvent {
  const LedStateChanged(this.state);

  final LedState state;
}

/// まだ Dart 側で解釈していない種別のイベント。
///
/// design.md 4.3 が挙げるイベントのうち、担当WPが未着手のものはここへ入る。
/// 捨てずに残すことで、実装漏れを検出できるようにする。
class UnhandledEmulatorEvent extends EmulatorEvent {
  const UnhandledEmulatorEvent(this.nativeKind);

  final int nativeKind;
}
