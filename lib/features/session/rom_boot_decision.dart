import '../../emulator/session_state.dart';
import 'rom_settings_state.dart';

/// ROM検証結果を受けて次に何をするかの判定（design.md 301、APP-06）。
enum RomBootAction {
  /// 何もしない（走査中、未初期化、またはすでに起動処理へ入っている）。
  none,

  /// 起動必須ROMが揃っている。自動的に起動してよい。
  launch,

  /// 起動必須ROMに異常がある、または走査自体が失敗した。
  showProblem,
}

/// [emulatorSession]と[romSettings]から[RomBootAction]を決める。
///
/// 起動必須6ファイル（`RomRole.bootRequired`）の異常だけを対象にする。
/// F-BASIC ROM（`RomRole.basicRequired`）の有無はBoot Modeの選択と
/// エミュレーターコア自身の振る舞いの話であり、起動を止める理由には
/// しない（DOSモードで媒体が空でも止めないのと同じ扱い）。
RomBootAction decideRomBootAction({
  required SessionState emulatorSession,
  required RomSettingsState romSettings,
}) {
  if (emulatorSession != SessionState.stopped) {
    return RomBootAction.none;
  }
  if (romSettings.isScanning || !romSettings.hasDirectory) {
    return RomBootAction.none;
  }
  if (!romSettings.scanFailed && (romSettings.inventory?.canBoot ?? false)) {
    return RomBootAction.launch;
  }
  if (romSettings.scanFailed || romSettings.inventory != null) {
    return RomBootAction.showProblem;
  }
  return RomBootAction.none;
}
