import '../../emulator/led_state.dart';
import '../../emulator/session_state.dart';
import '../display/screen_filter.dart';
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
    this.scanlineEnabled = false,
    this.hostFilter = HostScreenFilter.none,
    this.ledState = const LedState(),
    this.failureMessage,
    this.fddMedia = const {},
    this.fddLastAccessed = const {},
    this.fddDriveSettings = const {},
    this.fddBankNum = const {},
    this.fddCurBank = const {},
    this.fddSourceKind = const {},
    this.fddRecentFiles = const {},
    this.cmtInserted = false,
    this.cmtPlaying = false,
    this.cmtRecording = false,
    this.cmtPosition = 0,
    this.cmtMessage = 'Stop',
    this.cmtDriveSettings = const CmtDriveSettings(),
    this.cmtSoundSettings = const CmtSoundSettings(),
    this.cmtRecentFiles = const [],
    this.bootMode = BootMode.basic,
    this.cpuType = CpuType.fast,
    this.speedMultiplier = SpeedMultiplier.x1,
    this.fullSpeed = false,
    this.optionSwitches = const RunOptionSwitches(),
    this.soundVolumes = const SoundChannelVolumes(),
    this.fddMechanicalSoundEnabled = true,
    this.isRecording = false,
    this.isAutoKeying = false,
    this.romajiToKana = false,
    this.viewFps = 0,
    this.coreFps = 0,
  });

  final SessionState session;

  /// 画面を受け取る Texture のID。未接続なら null。
  final int? textureId;

  /// コアが返した論理解像度（VID-01）。
  final int frameWidth;
  final int frameHeight;

  /// 表示領域への合わせ方（VID-02）。`EmulatorController`が
  /// `PreferencesStore`へ永続化し、再起動後も復元する。
  final ScreenFit fit;

  /// ホスト側の走査線効果が有効かどうか（VID-04）。[fit]と同じく
  /// `EmulatorController`が永続化する。
  final bool scanlineEnabled;

  /// ホスト側のRGBフィルター選択（VID-04）。[fit]と同じく永続化する。
  final HostScreenFilter hostFilter;

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

  /// CMTに媒体が挿入されているか（CMT-01/CMT-02）。
  final bool cmtInserted;

  /// CMTが走行（再生）中かどうか（CMT-03）。
  final bool cmtPlaying;

  /// CMTが走行（録音）中かどうか（CMT-03）。
  final bool cmtRecording;

  /// CMTの走行位置（0〜100、CMT-05）。未挿入または再生中でなければ0。
  final int cmtPosition;

  /// CMTの状態メッセージ（CMT-05、upstream `DATAREC::get_message()`）。
  final String cmtMessage;

  /// CMTの波形整形設定（CMT-04）。
  final CmtDriveSettings cmtDriveSettings;

  /// CMTノイズ・CMT信号・CMT音声の個別有効化と、ノイズ・信号の音量
  /// （AUD-07）。
  final CmtSoundSettings cmtSoundSettings;

  /// CMTの最近使ったファイル（CMT-05、新しい順）。
  final List<CmtRecentFile> cmtRecentFiles;

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

  /// 標準OPNのFM・PSG、Beep、キーボード音、FDD機構音の個別音量
  /// （AUD-03）。永続化しないセッション内の状態
  /// （[optionSwitches]と同じ扱い、design.md「標準音声設定（M3、
  /// AUD-03）の実装方式」）。
  final SoundChannelVolumes soundVolumes;

  /// FDD内部機構音（ホスト側合成、readWriteのみ、AUD-04）の有効・無効。
  /// 永続化しないセッション内の状態（[soundVolumes]と同じ扱い）。
  final bool fddMechanicalSoundEnabled;

  /// 音声録音中かどうか（AUD-06）。永続化しないセッション内の状態。
  final bool isRecording;

  /// クリップボード文字列の自動キー入力中かどうか（INP-03）。永続化しない
  /// セッション内の状態。
  final bool isAutoKeying;

  /// ローマ字かな変換の有効・無効（INP-03）。永続化しないセッション内の
  /// 状態（[fddMechanicalSoundEnabled]と同じ扱い）。
  final bool romajiToKana;

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
    bool? scanlineEnabled,
    HostScreenFilter? hostFilter,
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
    bool? cmtInserted,
    bool? cmtPlaying,
    bool? cmtRecording,
    int? cmtPosition,
    String? cmtMessage,
    CmtDriveSettings? cmtDriveSettings,
    CmtSoundSettings? cmtSoundSettings,
    List<CmtRecentFile>? cmtRecentFiles,
    BootMode? bootMode,
    CpuType? cpuType,
    int? speedMultiplier,
    bool? fullSpeed,
    RunOptionSwitches? optionSwitches,
    SoundChannelVolumes? soundVolumes,
    bool? fddMechanicalSoundEnabled,
    bool? isRecording,
    bool? isAutoKeying,
    bool? romajiToKana,
    double? viewFps,
    double? coreFps,
  }) {
    return EmulatorViewState(
      session: session ?? this.session,
      textureId: clearTextureId ? null : (textureId ?? this.textureId),
      frameWidth: frameWidth ?? this.frameWidth,
      frameHeight: frameHeight ?? this.frameHeight,
      fit: fit ?? this.fit,
      scanlineEnabled: scanlineEnabled ?? this.scanlineEnabled,
      hostFilter: hostFilter ?? this.hostFilter,
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
      cmtInserted: cmtInserted ?? this.cmtInserted,
      cmtPlaying: cmtPlaying ?? this.cmtPlaying,
      cmtRecording: cmtRecording ?? this.cmtRecording,
      cmtPosition: cmtPosition ?? this.cmtPosition,
      cmtMessage: cmtMessage ?? this.cmtMessage,
      cmtDriveSettings: cmtDriveSettings ?? this.cmtDriveSettings,
      cmtSoundSettings: cmtSoundSettings ?? this.cmtSoundSettings,
      cmtRecentFiles: cmtRecentFiles ?? this.cmtRecentFiles,
      bootMode: bootMode ?? this.bootMode,
      cpuType: cpuType ?? this.cpuType,
      speedMultiplier: speedMultiplier ?? this.speedMultiplier,
      fullSpeed: fullSpeed ?? this.fullSpeed,
      optionSwitches: optionSwitches ?? this.optionSwitches,
      soundVolumes: soundVolumes ?? this.soundVolumes,
      fddMechanicalSoundEnabled:
          fddMechanicalSoundEnabled ?? this.fddMechanicalSoundEnabled,
      isRecording: isRecording ?? this.isRecording,
      isAutoKeying: isAutoKeying ?? this.isAutoKeying,
      romajiToKana: romajiToKana ?? this.romajiToKana,
      viewFps: viewFps ?? this.viewFps,
      coreFps: coreFps ?? this.coreFps,
    );
  }
}
