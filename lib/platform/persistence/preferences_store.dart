/// 軽量な設定値の保存先。
///
/// design.md 11.2 の`PreferencesStore`境界。OS標準の設定機構
/// （macOS/iOSは`NSUserDefaults`、Windowsはレジストリ相当、
/// LinuxはXDG_CONFIG_HOME、AndroidはDataStore）へ委譲する。
/// feature層は物理パスを組み立てず、この境界だけを利用する。
abstract interface class PreferencesStore {
  /// 設定スキーマの版。移行判定に使用する。
  static const String schemaVersionKey = 'schemaVersion';

  String? getString(String key);
  int? getInt(String key);
  double? getDouble(String key);
  bool? getBool(String key);

  Future<void> setString(String key, String value);
  Future<void> setInt(String key, int value);
  Future<void> setDouble(String key, double value);
  Future<void> setBool(String key, bool value);

  Future<void> remove(String key);

  /// 保留中の書込みを確定する。
  Future<void> flush();
}
