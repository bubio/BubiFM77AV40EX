import 'dart:ffi';

/// native/bridge/include/bubi_fm77av.h の POD 構造体と列挙に対応する定義。
///
/// ヘッダーとこのファイルは手作業で同期する。値や並びを変えるときは
/// 必ず両方を直し、`session_test` と `test/` の双方を通すこと。

/// `bfm_result`
abstract final class BfmResult {
  static const int ok = 0;
  static const int invalidArgument = 1;
  static const int invalidState = 2;
  static const int queueFull = 3;
  static const int noEvent = 4;
  static const int coreFailed = 5;
  static const int unsupported = 6;
  static const int internal = 7;

  /// rawイメージのサイズがFM7系の2D/2DDジオメトリのどちらとも一致しない、
  /// または変換形式の変換後media_typeが2D/2DD以外だった（M3 FDD-03）。
  static const int unsupportedGeometry = 8;

  /// 状態読込み対象ファイルの先頭バージョンが既知値と一致しない、または
  /// 読めない（M3 STA-02）。コア内部でさらに深い不一致を検出した場合は
  /// このコードでは表せず、現在の実行状態が静かに保たれるだけになる
  /// （design.md「状態保存（M3、STA-01/STA-02）の実装方式」）。
  static const int stateIncompatible = 9;
}

/// `bfm_state`
abstract final class BfmState {
  static const int stopped = 0;
  static const int starting = 1;
  static const int running = 2;
  static const int stopping = 3;
  static const int failed = 4;
}

/// `bfm_reset_kind`
abstract final class BfmResetKind {
  static const int normal = 0;
  static const int special = 1;
}

/// `bfm_boot_mode`。値は upstream の `config.boot_mode` と同じ。
abstract final class BfmBootMode {
  static const int basic = 0;
  static const int dos = 1;
}

/// `bfm_audio_latency`。Host > Sound の「オーディオバッファ」設定。
/// セッション生成後は変更できない。
abstract final class BfmAudioLatency {
  static const int ms50 = 0;
  static const int ms100 = 1;
  static const int ms200 = 2;
  static const int ms300 = 3;
}

/// `bfm_cpu_type`。値は upstream の `config.cpu_type` と同じ。
/// [BfmCommandKind.setCpuType] はコアの `update_config()` を呼ぶため、
/// リセットを待たずに反映される。
abstract final class BfmCpuType {
  static const int fast = 0; // 2.0MHz相当
  static const int slow = 1; // 1.2MHz
}

/// `bfm_fdd_media_type`。空ディスク作成（M3 FDD-05）の媒体種別。
abstract final class BfmFddMediaType {
  static const int media2D = 0;
  static const int media2DD = 1;
}

/// `bfm_sound_channel`。`BFM_CMD_SET_SOUND_VOLUME`（M3 AUD-03）のarg0。
abstract final class BfmSoundChannel {
  static const int opnFm = 0;
  static const int opnPsg = 1;
  static const int beep = 2;
  static const int keyboardBeep = 3;
  static const int fddMechanism = 4;
}

/// `bfm_cmt_control_op`。`BFM_CMD_CONTROL_CMT`（M4 CMT-03）のarg0。
/// 原作`.rc`の"Play Button"/"Stop Button"/"Fast Forward"/"Fast Rewind"に
/// 対応する。APSSは原作FM77AV40EXのメニューに配線されていないため含めない。
abstract final class BfmCmtControlOp {
  static const int play = 0;
  static const int stop = 1;
  static const int fastForward = 2;
  static const int fastRewind = 3;
}

/// `bfm_cmt_sound_kind`。`BFM_CMD_SET_CMT_SOUND_ENABLE`/
/// `BFM_CMD_SET_CMT_SOUND_VOLUME`（M4 AUD-07）のarg0。
/// [voice] は`BFM_CMD_SET_CMT_SOUND_VOLUME`には渡せない（upstream
/// `VM::set_sound_device_volume()`がCMT音声用の内部音量へ配線されておらず、
/// upstream改変禁止のため調整できない既知の制約。invalidArgumentになる）。
abstract final class BfmCmtSoundKind {
  static const int noise = 0;
  static const int signal = 1;
  static const int voice = 2;
}

/// `BFM_CMD_SET_OPTION_SWITCH` の arg0 に渡すビット。
///
/// この3ビットの組だけを毎回丸ごと置き換える（マージしない）。
/// サイクルスチールとHSYNC同期は即時反映されるが、拡張RAMはコアが
/// リセット時にしか読まないため次のリセットまで反映されない
/// （design.md 16.1）。
abstract final class BfmOptionSwitch {
  static const int cycleSteal = 0x1;
  static const int extendedRam = 0x2;
  static const int syncToHsync = 0x4;
}

/// `bfm_screen_filter`（`BfmCommandKind.setScreenFilter`のarg0、VID-04）。
abstract final class BfmScreenFilter {
  static const int none = 0;
  static const int rgb = 1;
}

/// `bfm_command_kind`。上位バイトが design.md 4.2 の分類に対応する。
///
/// WP1 で実装済みなのは [reset] と [specialReset] だけで、
/// ほかは型として予約されており [BfmResult.unsupported] で完了する。
abstract final class BfmCommandKind {
  static const int reset = 0x0100;
  static const int specialReset = 0x0101;

  static const int setSpeedMultiplier = 0x0200;
  static const int setFullSpeed = 0x0201;
  static const int setBootMode = 0x0202;
  static const int setCpuType = 0x0203;

  static const int insertFdd = 0x0300;
  static const int ejectFdd = 0x0301;
  static const int setFddWriteProtect = 0x0302;
  static const int setFddTiming = 0x0303;
  static const int setFddCrcCheck = 0x0304;
  static const int createBlankFdd = 0x0305;
  static const int insertCmt = 0x0310;
  static const int ejectCmt = 0x0311;
  static const int controlCmt = 0x0312;
  static const int setCmtWaveShaping = 0x0313;
  static const int setCmtSoundEnable = 0x0314;
  static const int setCmtSoundVolume = 0x0315;
  static const int setCmtFastLoad = 0x0316;

  static const int keyDown = 0x0400;
  static const int keyUp = 0x0401;
  static const int mouse = 0x0402;
  static const int joystick = 0x0403;
  static const int autoKey = 0x0404;

  static const int setSoundType = 0x0500;
  static const int setOptionSwitch = 0x0501;
  static const int setVolume = 0x0502;
  static const int setFrameRate = 0x0503;
  static const int setSoundVolume = 0x0504;
  static const int setScreenFilter = 0x0505;
  static const int setScreenPower = 0x0506;

  static const int saveState = 0x0600;
  static const int loadState = 0x0601;

  static const int debuggerOpen = 0x0700;
  static const int debuggerClose = 0x0701;
  static const int debuggerExecute = 0x0702;
}

/// `bfm_event_kind`
abstract final class BfmEventKind {
  static const int lifecycleChanged = 0;
  static const int commandCompleted = 1;
  static const int error = 2;
  static const int mediaChanged = 3;
  static const int mediaAccessChanged = 4;
  static const int tapePositionChanged = 5;
  static const int fddMechanical = 6;
  static const int ledChanged = 7;
  static const int screenModeChanged = 8;
  static const int performanceChanged = 9;
  static const int stateSlotChanged = 10;
  static const int debuggerStopped = 11;
}

/// `bfm_session`（不透明ハンドル）
final class BfmSession extends Opaque {}

/// `bfm_create_options`
final class BfmCreateOptions extends Struct {
  /// コアがアプリケーションデータを置く位置。プロセス全体で1つに限る。
  external Pointer<Char> homeDir;

  /// 利用者が選んだROMディレクトリ。null なら結線しない。
  external Pointer<Char> romDir;

  @Int32()
  external int bootMode;

  @Uint32()
  external int commandQueueCapacity;
  @Uint32()
  external int eventQueueCapacity;

  /// `bfm_audio_latency`。既定は0（BFM_AUDIO_LATENCY_50MS、ゼロ初期化と一致）。
  @Int32()
  external int audioLatency;
}

/// `bfm_command`
final class BfmCommand extends Struct {
  @Uint32()
  external int kind;
  @Int32()
  external int reserved;
  @Int64()
  external int arg0;
  @Int64()
  external int arg1;

  /// 呼び出し中だけ借用される。ネイティブ側が複製するため、
  /// 呼び出し後は解放してよい。
  external Pointer<Char> text;
}

/// `bfm_event`
final class BfmEvent extends Struct {
  @Uint32()
  external int kind;
  @Int32()
  external int code;
  @Uint64()
  external int commandId;
  @Int64()
  external int arg0;
  @Int64()
  external int arg1;
}

/// `bfm_stats`
final class BfmStats extends Struct {
  @Uint64()
  external int framesRun;
  @Uint64()
  external int commandsAccepted;
  @Uint64()
  external int commandsRejected;
  @Uint64()
  external int eventsDropped;

  /// Core thread 以外から VM 操作境界へ入った回数。常に 0 でなければならない。
  @Uint64()
  external int vmAccessViolations;

  /// 公開したフレーム数。画面が変わらないフレームは数えない（VID-07）。
  @Uint64()
  external int framesPublished;

  /// 書ける面が尽きて捨てたフレーム数。
  @Uint64()
  external int framesDropped;

  /// Core threadが`vm->create_sound()`で取り出したPCMフレーム数の累計。
  @Uint64()
  external int audioFramesProduced;

  /// `bfm_read_audio`が無音で埋めたフレーム数の累計。
  @Uint64()
  external int audioUnderrunFrames;

  /// 読み手が追いつかず最古から捨てたフレーム数の累計。
  @Uint64()
  external int audioOverrunFrames;
}

/// `bfm_cmt_status`（M4 CMT-05）。[message] はNUL終端。
final class BfmCmtStatus extends Struct {
  @Int32()
  external int inserted;
  @Int32()
  external int playing;
  @Int32()
  external int recording;
  @Int32()
  external int position;

  @Array(128)
  external Array<Uint8> message;
}

/// `bfm_video_frame`。借りているあいだ内容も大きさも変わらない。
///
/// [pixels] は BGRA8888、上から下へ、幅×高さの連続領域。
/// アルファはブリッジが 0xff で埋めてある。
final class BfmVideoFrame extends Struct {
  external Pointer<Uint32> pixels;
  @Uint32()
  external int width;
  @Uint32()
  external int height;
  @Uint32()
  external int reserved;
  @Uint64()
  external int generation;
}
