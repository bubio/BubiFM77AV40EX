import 'package:bubifm77av40ex_platform/src/xdg_user_directory.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('設定済みのユーザーディレクトリはそのまま返す', () {
    expect(
      normalizeXdgUserDirectory('/home/user/Pictures', '/home/user'),
      '/home/user/Pictures',
    );
  });

  test('未設定でホームが返った場合はnull', () {
    expect(normalizeXdgUserDirectory('/home/user', '/home/user'), isNull);
    expect(normalizeXdgUserDirectory('/home/user/', '/home/user'), isNull);
  });

  test('xdg-user-dirがない、または空の出力はnull', () {
    expect(normalizeXdgUserDirectory(null, '/home/user'), isNull);
    expect(normalizeXdgUserDirectory('', '/home/user'), isNull);
  });
}
