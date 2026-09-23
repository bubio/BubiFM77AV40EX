import 'package:bubifm77av40ex/app/window_title.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('バージョンとビルド番号を並べる', () {
    expect(
      formatWindowTitle(version: '0.1.0', buildNumber: '1'),
      'BubiFM77AV40EX 0.1.0 (1)',
    );
  });

  test('ビルド番号が空なら省く', () {
    expect(
      formatWindowTitle(version: '0.1.0', buildNumber: ''),
      'BubiFM77AV40EX 0.1.0',
    );
  });
}
