import 'package:flutter/widgets.dart';

import '../screen_fit.dart';

/// コアの画面を出す。
///
/// 画素はネイティブ側がTextureへ直接書き込むため、ここを通らない
/// （design.md 16.1）。このWidgetが決めるのは置き方だけである。
class EmulatorScreen extends StatelessWidget {
  const EmulatorScreen({
    required this.textureId,
    required this.frameWidth,
    required this.frameHeight,
    this.fit = ScreenFit.aspect,
    super.key,
  });

  final int textureId;
  final int frameWidth;
  final int frameHeight;
  final ScreenFit fit;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = fitScreen(
          frame: Size(frameWidth.toDouble(), frameHeight.toDouble()),
          available: Size(constraints.maxWidth, constraints.maxHeight),
          fit: fit,
        );
        if (size.isEmpty) {
          return const SizedBox.shrink();
        }
        return Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            // filterQuality は既定のまま。走査線やフィルターはVID-04（P1）で
            // 扱うため、ここでは倍率だけを決める。
            child: Texture(textureId: textureId),
          ),
        );
      },
    );
  }
}
