import 'package:shared_preferences/shared_preferences.dart';

import 'preferences_store.dart';

/// OS標準の設定機構を使う [PreferencesStore]（design.md 11.2）。
///
/// macOSでは`NSUserDefaults`へ書かれる。値の意味づけはfeature層が持ち、
/// ここは型と鍵の受け渡しだけを行う。
class OsPreferencesStore implements PreferencesStore {
  OsPreferencesStore._(this._preferences);

  static Future<OsPreferencesStore> open() async {
    return OsPreferencesStore._(await SharedPreferences.getInstance());
  }

  final SharedPreferences _preferences;

  @override
  String? getString(String key) => _preferences.getString(key);

  @override
  int? getInt(String key) => _preferences.getInt(key);

  @override
  double? getDouble(String key) => _preferences.getDouble(key);

  @override
  bool? getBool(String key) => _preferences.getBool(key);

  @override
  Future<void> setString(String key, String value) =>
      _preferences.setString(key, value);

  @override
  Future<void> setInt(String key, int value) => _preferences.setInt(key, value);

  @override
  Future<void> setDouble(String key, double value) =>
      _preferences.setDouble(key, value);

  @override
  Future<void> setBool(String key, bool value) =>
      _preferences.setBool(key, value);

  @override
  Future<void> remove(String key) => _preferences.remove(key);

  /// `shared_preferences`は`set`のたびに書き出すため、確定は不要である。
  ///
  /// `reload()`はプラットフォーム側から読み直す操作であり、
  /// 保留中の書込みを確定する`flush`とは逆である。呼び間違えないよう
  /// 何もしない実装にしておく。
  @override
  Future<void> flush() async {}
}
