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
    this.fddMedia = const {},
    this.fddLastAccessed = const {},
    this.bootMode = BootMode.basic,
    this.viewFps = 0,
    this.coreFps = 0,
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

  /// FD1(0)/FD2(1)に挿入中の媒体の表示名。キーがなければ未挿入（FDD-01）。
  final Map<int, String> fddMedia;

  /// FD1/FD2が直近でアクセスされた時刻。キーがなければ記録なし。
  ///
  /// ネイティブ側はread-and-clearのポーリングで通知するため、これは
  /// 「その時点でアクセスがあった」というスナップショットである。
  /// 持続的なランプ点灯として見せるかどうかは受け手が自分で
  /// タイムアウトを判断する（design.md 16.1）。
  final Map<int, DateTime> fddLastAccessed;

  /// 起動に使ったブートモード（design.md 12.4のステータスバー`[BASIC|DOS]`）。
  ///
  /// 設定画面の選択値そのものではなく、実際に起動した値。反映は次回の
  /// リセットまたは再起動からのため、両者は一時的に食い違いうる。
  final BootMode bootMode;

  /// 直近1秒間に描画側へ公開したフレーム数（design.md 12.4 View FPS）。
  final double viewFps;

  /// 直近1秒間にCore threadが進めたフレーム数（design.md 12.4 Core FPS）。
  final double coreFps;

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
    Map<int, String>? fddMedia,
    Map<int, DateTime>? fddLastAccessed,
    BootMode? bootMode,
    double? viewFps,
    double? coreFps,
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
      fddMedia: fddMedia ?? this.fddMedia,
      fddLastAccessed: fddLastAccessed ?? this.fddLastAccessed,
      bootMode: bootMode ?? this.bootMode,
      viewFps: viewFps ?? this.viewFps,
      coreFps: coreFps ?? this.coreFps,
    );
  }
}
