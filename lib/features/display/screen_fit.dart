import 'dart:math' as math;

import 'dart:ui' show Size;

/// 表示領域に対する画面の合わせ方（VID-02）。
enum ScreenFit {
  /// アスペクト比を保ったまま、領域に収まる最大へ拡大する。
  aspect,

  /// アスペクト比を保ち、拡大率を整数に丸める。画素が均等になる。
  integer,

  /// 領域を埋める。アスペクト比は崩れる。
  fill,
}

/// [available] の中に画面を置いたときの大きさを返す。
///
/// [frame] はコアが返した論理解像度をそのまま使う（縦横比の補正はしない）。
/// upstream（`native/core/upstream/src/win32/osd_screen.cpp`の
/// `window_stretch_type`）のウィンドウモード既定値は無補正表示
/// （"Window Stretch 1"）で、4:3への引き伸ばし（"Window Stretch 2"、
/// 640×400を見かけ640×480にする）は利用者が明示的に選ぶ別メニューの
/// オプションであり既定ではない。ウィンドウモードでは常に前者を使う
/// （design.md「Window x1/x2/…の実装方式」、利用者からの指摘で訂正）。
Size fitScreen({
  required Size frame,
  required Size available,
  required ScreenFit fit,
}) {
  if (frame.width <= 0 ||
      frame.height <= 0 ||
      available.width <= 0 ||
      available.height <= 0) {
    return Size.zero;
  }

  if (fit == ScreenFit.fill) {
    return available;
  }

  final double scale = math.min(
    available.width / frame.width,
    available.height / frame.height,
  );

  if (fit == ScreenFit.integer) {
    // 1未満へは丸めない。丸めると領域より大きいまま残り、はみ出す。
    final double integerScale = scale >= 1 ? scale.floorToDouble() : scale;
    return Size(frame.width * integerScale, frame.height * integerScale);
  }

  return Size(frame.width * scale, frame.height * scale);
}
