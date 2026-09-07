/// C ABI の整数値と `lib/emulator/` の型との変換。
///
/// 副作用を持たず、ネイティブライブラリを読み込まないため、
/// 単体テストから直接検証できる。
library;

import 'package:bubi_fm77av40ex_core/bubi_fm77av40ex_core.dart';

import '../../emulator/emulator_error.dart';
import '../../emulator/emulator_event.dart';
import '../../emulator/led_state.dart';
import '../../emulator/session_state.dart';

/// `bfm_result` を [EmulatorErrorCode] へ変換する。
///
/// 未知の値は [EmulatorErrorCode.unknown] にする。ヘッダーとの同期漏れを
/// 別のエラーへ吸収させない。
EmulatorErrorCode errorCodeFromNative(int value) => switch (value) {
  BfmResult.invalidArgument => EmulatorErrorCode.invalidArgument,
  BfmResult.invalidState => EmulatorErrorCode.invalidState,
  BfmResult.queueFull => EmulatorErrorCode.queueFull,
  BfmResult.noEvent => EmulatorErrorCode.noEvent,
  BfmResult.coreFailed => EmulatorErrorCode.coreFailed,
  BfmResult.unsupported => EmulatorErrorCode.unsupported,
  BfmResult.internal => EmulatorErrorCode.internal,
  BfmResult.unsupportedGeometry => EmulatorErrorCode.unsupportedGeometry,
  _ => EmulatorErrorCode.unknown,
};

/// `bfm_state` を [SessionState] へ変換する。
///
/// 未知の値は [SessionState.failed] にする。状態が読めないまま
/// 動いていると誤認させないためである。
SessionState sessionStateFromNative(int value) => switch (value) {
  BfmState.stopped => SessionState.stopped,
  BfmState.starting => SessionState.starting,
  BfmState.running => SessionState.running,
  BfmState.stopping => SessionState.stopping,
  BfmState.failed => SessionState.failed,
  _ => SessionState.failed,
};

/// [ResetKind] を `bfm_reset_kind` へ変換する。
int resetKindToNative(ResetKind kind) => switch (kind) {
  ResetKind.normal => BfmResetKind.normal,
  ResetKind.special => BfmResetKind.special,
};

/// [BootMode] を `bfm_boot_mode` へ変換する。
int bootModeToNative(BootMode mode) => switch (mode) {
  BootMode.basic => BfmBootMode.basic,
  BootMode.dos => BfmBootMode.dos,
};

/// [CpuType] を `bfm_cpu_type` へ変換する。
int cpuTypeToNative(CpuType type) => switch (type) {
  CpuType.fast => BfmCpuType.fast,
  CpuType.slow => BfmCpuType.slow,
};

/// [FddMediaType] を `bfm_fdd_media_type` へ変換する。
int fddMediaTypeToNative(FddMediaType type) => switch (type) {
  FddMediaType.d2 => BfmFddMediaType.media2D,
  FddMediaType.d2dd => BfmFddMediaType.media2DD,
};

/// [RunOptionSwitches] を `BFM_CMD_SET_OPTION_SWITCH` の arg0 へ変換する。
int runOptionSwitchesToNative(RunOptionSwitches switches) =>
    (switches.cycleSteal ? BfmOptionSwitch.cycleSteal : 0) |
    (switches.extendedRam ? BfmOptionSwitch.extendedRam : 0) |
    (switches.syncToHsync ? BfmOptionSwitch.syncToHsync : 0);

/// [SoundChannel] を `bfm_sound_channel` へ変換する（M3 AUD-03）。
int soundChannelToNative(SoundChannel channel) => switch (channel) {
  SoundChannel.opnFm => BfmSoundChannel.opnFm,
  SoundChannel.opnPsg => BfmSoundChannel.opnPsg,
  SoundChannel.beep => BfmSoundChannel.beep,
  SoundChannel.keyboardBeep => BfmSoundChannel.keyboardBeep,
  SoundChannel.fddMechanism => BfmSoundChannel.fddMechanism,
};

/// 0.0〜1.0の音量を`BFM_CMD_SET_SOUND_VOLUME`のarg1（デシベル、0.5dB刻み、
/// 0=最大）へ変換する（M3 AUD-03）。範囲外はクランプする。
///
/// コアが受理する範囲は[-192, 0]（-96dB相当まで）だが、そのまま線形に
/// 割り当てるとdB自体が対数のため、スライダー後半のごく一部（0.9〜1.0）
/// にしか実用域が乗らない。実用的な操作幅にするため、UIの0.0〜1.0は
/// -60dB（実質無音）〜0dB（最大）へ線形に割り当てる（unit=-120〜0）。
int soundVolumeToDecibel(double volume) =>
    (volume.clamp(0.0, 1.0) * 120).round() - 120;

/// `bfm_event` の各フィールドから [EmulatorEvent] を組み立てる。
EmulatorEvent emulatorEventFromNative({
  required int kind,
  required int code,
  required int commandId,
  required int arg0,
  required int arg1,
}) => switch (kind) {
  BfmEventKind.lifecycleChanged => LifecycleChanged(
    sessionStateFromNative(arg0),
  ),
  BfmEventKind.commandCompleted => CommandCompleted(
    commandId,
    error: code == BfmResult.ok ? null : errorCodeFromNative(code),
  ),
  BfmEventKind.error => EmulatorErrorOccurred(errorCodeFromNative(code)),
  BfmEventKind.screenModeChanged => ScreenModeChanged(arg0, arg1),
  BfmEventKind.ledChanged => LedStateChanged(LedState.fromBits(arg0)),
  BfmEventKind.mediaChanged => MediaChanged(arg0, inserted: arg1 != 0),
  // BFM_EVENT_MEDIA_ACCESS_CHANGEDは未使用（bubi_fm77av.h参照）。
  // アクセス状態はFfiEmulatorSessionがbfm_get_media_accessを
  // ポーリングして合成する（native_conversions.dartのdriveSetFromBits）。
  _ => UnhandledEmulatorEvent(kind),
};

/// FD1/FD2アクセス状態のビット合成（0x1=FD1、0x2=FD2）をドライブ番号の
/// 集合へ変換する。
Set<int> driveSetFromBits(int bits) => {
  for (var drive = 0; drive < 2; drive++)
    if ((bits & (1 << drive)) != 0) drive,
};

/// エラーコードに対応する日本語以外の識別可能な説明。
///
/// 利用者向けの文言は `features` 側でローカライズする。ここは診断用に留める。
String describeErrorCode(EmulatorErrorCode code) => switch (code) {
  EmulatorErrorCode.invalidArgument =>
    'invalid argument passed to the core boundary',
  EmulatorErrorCode.invalidState =>
    'operation is not allowed in the current state',
  EmulatorErrorCode.queueFull => 'the command queue is saturated',
  EmulatorErrorCode.noEvent => 'no event is available',
  EmulatorErrorCode.coreFailed => 'the core thread failed',
  EmulatorErrorCode.unsupported =>
    'the command kind is defined but not implemented yet',
  EmulatorErrorCode.internal =>
    'an unexpected exception was contained at the boundary',
  EmulatorErrorCode.unsupportedGeometry =>
    'the media geometry is not 2D/2DD after size check or conversion',
  EmulatorErrorCode.unknown =>
    'an unknown result code was returned by the core',
};
