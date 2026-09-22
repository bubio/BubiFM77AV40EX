import 'dart:io';

import 'package:xdg_directories/xdg_directories.dart' as xdg;

/// LinuxのXDGユーザーディレクトリ（`xdg-user-dir PICTURES`など）の
/// 絶対パス。定まらなければ`null`を返す。
///
/// `xdg-user-dir`は、`user-dirs.dirs`に設定がない名前に対してホーム
/// ディレクトリそのものを返す。ホーム直下へアプリのフォルダーを作らない
/// よう、その場合も`null`とし、呼び出し側を保存ダイアログなどの代替手段
/// へ切り替えさせる。
String? xdgUserDirectoryPath(String name) {
  final String? path;
  try {
    path = xdg.getUserDirectory(name)?.path;
  } on ProcessException {
    return null;
  }
  return normalizeXdgUserDirectory(path, Platform.environment['HOME']);
}

/// `xdg-user-dir`の出力[path]を、使えるディレクトリか`null`へ正規化する。
String? normalizeXdgUserDirectory(String? path, String? home) {
  if (path == null || path.isEmpty) {
    return null;
  }
  if (home != null && _trimTrailingSlash(path) == _trimTrailingSlash(home)) {
    return null;
  }
  return path;
}

String _trimTrailingSlash(String value) {
  return value.length > 1 && value.endsWith('/')
      ? value.substring(0, value.length - 1)
      : value;
}
