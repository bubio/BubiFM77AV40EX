import 'dart:ui' show Size;

import 'package:bubi_fm77av40ex/features/display/screen_fit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VID-02 表示領域への合わせ方', () {
    test('アスペクト比維持は領域に収まる最大にする', () {
      final size = fitScreen(
        frame: const Size(640, 400),
        available: const Size(1280, 1000),
        fit: ScreenFit.aspect,
      );
      // 640x400 の見かけは 640x480（4:3）。横で1280/640=2.0、
      // 縦で1000/480=2.08 なので横が効く。
      expect(size.width, 1280);
      expect(size.height, closeTo(960, 0.001));
    });

    test('整数倍は拡大率を切り捨てる', () {
      final size = fitScreen(
        frame: const Size(640, 400),
        available: const Size(1500, 1500),
        fit: ScreenFit.integer,
      );
      // 横1500/640=2.34、縦1500/480=3.12 → 2倍。
      expect(size.width, 1280);
      expect(size.height, closeTo(960, 0.001));
    });

    test('整数倍でも領域より小さいときは縮小する', () {
      final size = fitScreen(
        frame: const Size(640, 400),
        available: const Size(320, 240),
        fit: ScreenFit.integer,
      );
      // 1倍にも満たない。切り上げるとはみ出すため、そのまま縮める。
      expect(size.width, closeTo(320, 0.001));
      expect(size.height, closeTo(240, 0.001));
    });

    test('領域充填は領域そのものを返す', () {
      final size = fitScreen(
        frame: const Size(640, 400),
        available: const Size(1000, 300),
        fit: ScreenFit.fill,
      );
      expect(size, const Size(1000, 300));
    });

    test('640×200も4:3で表示する', () {
      // 論理解像度の縦横比は3.2だが、実機の見かけは4:3である。
      // 補正しないとこの解像度だけ縦に潰れる。
      final wide = fitScreen(
        frame: const Size(640, 200),
        available: const Size(1280, 2000),
        fit: ScreenFit.aspect,
      );
      final tall = fitScreen(
        frame: const Size(640, 400),
        available: const Size(1280, 2000),
        fit: ScreenFit.aspect,
      );
      expect(wide, tall);
    });

    test('大きさが0なら0を返す', () {
      expect(
        fitScreen(
          frame: Size.zero,
          available: const Size(100, 100),
          fit: ScreenFit.aspect,
        ),
        Size.zero,
      );
      expect(
        fitScreen(
          frame: const Size(640, 400),
          available: Size.zero,
          fit: ScreenFit.aspect,
        ),
        Size.zero,
      );
    });
  });
}
