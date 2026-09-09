import 'dart:ui' show Size;

import 'package:bubifm77av40ex/features/display/screen_fit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VID-02 表示領域への合わせ方', () {
    test('アスペクト比維持は領域に収まる最大にする', () {
      final size = fitScreen(
        frame: const Size(640, 400),
        available: const Size(1280, 1000),
        fit: ScreenFit.aspect,
      );
      // 横で1280/640=2.0、縦で1000/400=2.5なので横が効く。
      expect(size.width, 1280);
      expect(size.height, closeTo(800, 0.001));
    });

    test('整数倍は拡大率を切り捨てる', () {
      final size = fitScreen(
        frame: const Size(640, 400),
        available: const Size(1500, 1500),
        fit: ScreenFit.integer,
      );
      // 横1500/640=2.34、縦1500/400=3.75 → 2倍。
      expect(size.width, 1280);
      expect(size.height, closeTo(800, 0.001));
    });

    test('整数倍でも領域より小さいときは縮小する', () {
      final size = fitScreen(
        frame: const Size(640, 400),
        available: const Size(320, 200),
        fit: ScreenFit.integer,
      );
      // 1倍にも満たない。切り上げるとはみ出すため、そのまま縮める。
      expect(size.width, closeTo(320, 0.001));
      expect(size.height, closeTo(200, 0.001));
    });

    test('領域充填は領域そのものを返す', () {
      final size = fitScreen(
        frame: const Size(640, 400),
        available: const Size(1000, 300),
        fit: ScreenFit.fill,
      );
      expect(size, const Size(1000, 300));
    });

    test('解像度ごとの縦横比をそのまま使う（4:3補正はしない）', () {
      // upstreamのウィンドウモード既定値（"Window Stretch 1"）は無補正
      // 表示で、4:3への引き伸ばしは利用者が明示的に選ぶ別メニューの
      // オプション（既定ではない）。640×200（縦横比3.2）は640×400
      // （縦横比1.6）と同じ大きさにはならない。
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
      expect(wide, isNot(tall));
      expect(wide, const Size(1280, 400));
      expect(tall, const Size(1280, 800));
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
