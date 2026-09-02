/// UI言語の選択（design.md 12.2 `Host > Language`）。
///
/// `system`はOSのロケールへ委ねる。`MaterialApp.locale`へは
/// `system`のときだけ`null`を渡す。
enum AppLocaleMode { system, english, japanese }

/// アプリ全体の設定（design.md 11.3 `NSUserDefaults`相当）。
///
/// ROMフォルダーやブートモードのようなROM境界の設定は
/// `RomSettingsController`が持つ。ここはホスト側だけの設定を持つ。
class SettingsState {
  const SettingsState({
    this.localeMode = AppLocaleMode.system,
    this.masterVolume = 1.0,
  });

  final AppLocaleMode localeMode;

  /// 0.0（無音）から1.0（最大）。SoLoudの`globalVolume`へそのまま渡す。
  final double masterVolume;

  SettingsState copyWith({AppLocaleMode? localeMode, double? masterVolume}) {
    return SettingsState(
      localeMode: localeMode ?? this.localeMode,
      masterVolume: masterVolume ?? this.masterVolume,
    );
  }
}
