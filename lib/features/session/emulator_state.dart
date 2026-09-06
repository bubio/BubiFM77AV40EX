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
    this.fddDriveSettings = const {},
    this.fddBankNum = const {},
    this.fddCurBank = const {},
    this.fddSourceKind = const {},
    this.fddRecentFiles = const {},
    this.bootMode = BootMode.basic,
    this.cpuType = CpuType.fast,
    this.speedMultiplier = SpeedMultiplier.x1,
    this.fullSpeed = false,
    this.optionSwitches = const RunOptionSwitches(),
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

  /// FD1/FD2ごとの書込み保護・タイミング補正・CRCエラー無視（FDD-06）。
  /// キーがなければ既定値（すべて無効）。
  final Map<int, FddDriveSettings> fddDriveSettings;

  /// FD1/FD2に挿入中のD88の総バンク数（FDD-04）。キーがなければ未挿入。
  final Map<int, int> fddBankNum;

  /// FD1/FD2に挿入中のD88の現在のバンク番号（FDD-04）。
  final Map<int, int> fddCurBank;

  /// FD1/FD2に挿入中の媒体の由来（design.md 9.1）。`Save As D88…`は
  /// native container以外のときだけ有効にする（FDD-09）。
  final Map<int, DiskSourceKind> fddSourceKind;

  /// FD1/FD2ごとの最近使ったファイル（FDD-07、新しい順）。
  final Map<int, List<FddRecentFile>> fddRecentFiles;

  /// 起動に使ったブートモード（design.md 12.4のステータスバー`[BASIC|DOS]`）。
  ///
  /// 設定画面の選択値そのものではなく、実際に起動した値。反映は次回の
  /// リセットまたは再起動からのため、両者は一時的に食い違いうる。
  final BootMode bootMode;

  /// 現在のCPU種別（SYS-05）。コアの`update_config()`経由で即時反映
  /// されるため、選択値と実際の値は常に一致する（design.md 12.4）。
  final CpuType cpuType;

  /// 現在のCPU速度倍率（SYS-03）。[SpeedMultiplier]の値。
  final int speedMultiplier;

  /// 無制限速度（Full Speed、SYS-03の「無制限」）が有効かどうか。
  final bool fullSpeed;

  /// サイクルスチール・拡張RAM・HSYNC同期の現在値（SYS-06）。
  /// 拡張RAMだけは次のリセットまで実際の挙動に反映されない。
  final RunOptionSwitches optionSwitches;

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
    Map<int, FddDriveSettings>? fddDriveSettings,
    Map<int, int>? fddBankNum,
    Map<int, int>? fddCurBank,
    Map<int, DiskSourceKind>? fddSourceKind,
    Map<int, List<FddRecentFile>>? fddRecentFiles,
    BootMode? bootMode,
    CpuType? cpuType,
    int? speedMultiplier,
    bool? fullSpeed,
    RunOptionSwitches? optionSwitches,
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
      fddDriveSettings: fddDriveSettings ?? this.fddDriveSettings,
      fddBankNum: fddBankNum ?? this.fddBankNum,
      fddCurBank: fddCurBank ?? this.fddCurBank,
      fddSourceKind: fddSourceKind ?? this.fddSourceKind,
      fddRecentFiles: fddRecentFiles ?? this.fddRecentFiles,
      bootMode: bootMode ?? this.bootMode,
      cpuType: cpuType ?? this.cpuType,
      speedMultiplier: speedMultiplier ?? this.speedMultiplier,
      fullSpeed: fullSpeed ?? this.fullSpeed,
      optionSwitches: optionSwitches ?? this.optionSwitches,
      viewFps: viewFps ?? this.viewFps,
      coreFps: coreFps ?? this.coreFps,
    );
  }
}
