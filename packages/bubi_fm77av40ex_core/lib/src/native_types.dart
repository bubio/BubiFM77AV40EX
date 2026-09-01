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
  static const int insertCmt = 0x0310;
  static const int ejectCmt = 0x0311;
  static const int controlCmt = 0x0312;

  static const int keyDown = 0x0400;
  static const int keyUp = 0x0401;
  static const int mouse = 0x0402;
  static const int joystick = 0x0403;
  static const int autoKey = 0x0404;

  static const int setSoundType = 0x0500;
  static const int setOptionSwitch = 0x0501;
  static const int setVolume = 0x0502;
  static const int setFrameRate = 0x0503;

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
