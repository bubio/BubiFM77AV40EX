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

/// コアの論理解像度は縦横比が一定ではない。
///
/// 320×200と640×400は縦横比が1.6、640×200は3.2になるが、実機の表示は
/// どれも同じ4:3である。画素の縦横比を補正しないと、640×200の画面だけが
/// 縦に潰れて見える。
const double displayAspectRatio = 4 / 3;

/// [available] の中に画面を置いたときの大きさを返す。
///
/// [frame] はコアが返した論理解像度で、縦横比の補正はここで行う。
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

  // 実機の縦横比に合わせた「見かけの大きさ」を基準にする。
  final double targetHeight = frame.width / displayAspectRatio;
  final double scale = math.min(
    available.width / frame.width,
    available.height / targetHeight,
  );

  if (fit == ScreenFit.integer) {
    // 1未満へは丸めない。丸めると領域より大きいまま残り、はみ出す。
    final double integerScale = scale >= 1 ? scale.floorToDouble() : scale;
    return Size(frame.width * integerScale, targetHeight * integerScale);
  }

  return Size(frame.width * scale, targetHeight * scale);
}
