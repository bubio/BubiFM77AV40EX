import '../../emulator/led_state.dart';
import '../../emulator/session_state.dart';
import '../display/screen_fit.dart';

/// エミュレーター画面の状態。
///
/// 画素も音声もここには入れない。保持するのは最新のスナップショットだけ
/// である（design.md 4.3）。
class EmulatorViewState {
  const EmulatorViewState({
    this.session = SessionState.stopped,
    this.textureId,
    this.frameWidth = 640,
    this.frameHeight = 400,
    this.fit = ScreenFit.aspect,
    this.ledState = const LedState(),
    this.failureMessage,
  });

  final SessionState session;

  /// 画面を受け取る Texture のID。未接続なら null。
  final int? textureId;

  /// コアが返した論理解像度（VID-01）。
  final int frameWidth;
  final int frameHeight;

  /// 表示領域への合わせ方（VID-02）。
  final ScreenFit fit;

  /// INS、KANA、CAPSの意味づけ済み状態（INP-02）。
  final LedState ledState;

  /// 起動に失敗したときの説明。成功していれば null。
  final String? failureMessage;

  bool get isRunning => session == SessionState.running;

  bool get canShowScreen => textureId != null && isRunning;

  EmulatorViewState copyWith({
    SessionState? session,
    int? textureId,
    bool clearTextureId = false,
    int? frameWidth,
    int? frameHeight,
    ScreenFit? fit,
    LedState? ledState,
    String? failureMessage,
    bool clearFailure = false,
  }) {
    return EmulatorViewState(
      session: session ?? this.session,
      textureId: clearTextureId ? null : (textureId ?? this.textureId),
      frameWidth: frameWidth ?? this.frameWidth,
      frameHeight: frameHeight ?? this.frameHeight,
      fit: fit ?? this.fit,
      ledState: ledState ?? this.ledState,
      failureMessage: clearFailure
          ? null
          : (failureMessage ?? this.failureMessage),
    );
  }
}
