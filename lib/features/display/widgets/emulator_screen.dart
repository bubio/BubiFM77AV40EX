import 'dart:ui' show FragmentProgram, FragmentShader;

import 'package:flutter/widgets.dart';

import '../screen_filter.dart';
import '../screen_fit.dart';
import '../shader_filters.dart';

/// コアの画面を出す。
///
/// 画素はネイティブ側がTextureへ直接書き込むため、ここを通らない
/// （design.md 16.1）。このWidgetが決めるのは置き方と走査線の重ね掛けで
/// ある。走査線はテクスチャの画素を読まない位置だけのshaderのため、
/// `ShaderMask`（`BlendMode.modulate`）で下地へ掛け合わせる。
///
/// RGBフィルター（VID-04）はネイティブ側が移植元と同じ計算で掛け、
/// 画面の倍率倍の大きさの面をTextureへ渡す。倍率は移植元と同じく表示の
/// 大きさから求め、[onScreenPowerChanged]で知らせる。
class EmulatorScreen extends StatelessWidget {
  const EmulatorScreen({
    required this.textureId,
    required this.frameWidth,
    required this.frameHeight,
    this.fit = ScreenFit.aspect,
    this.scanlineEnabled = false,
    this.filter = HostScreenFilter.none,
    this.onScreenPowerChanged,
    super.key,
  });

  final int textureId;
  final int frameWidth;
  final int frameHeight;
  final ScreenFit fit;
  final bool scanlineEnabled;
  final HostScreenFilter filter;

  /// 表示の大きさから求めたRGBフィルターの倍率（横・縦）を知らせる。
  /// 大きさが変わらなくても呼ぶことがあるため、受け手が重複を除く。
  final void Function(int x, int y)? onScreenPowerChanged;

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
        final notify = onScreenPowerChanged;
        if (notify != null) {
          final power = screenPowerFor(
            displaySize: size,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
          );
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => notify(power.x, power.y),
          );
        }
        Widget screen = Texture(
          textureId: textureId,
          // フィルター済みの面は1画素ごとの明暗・色の並びそのものが効果の
          // ため、移植元（StretchBlt の COLORONCOLOR）と同じく補間しない。
          filterQuality: filter == HostScreenFilter.rgb
              ? FilterQuality.none
              : FilterQuality.low,
        );
        if (scanlineEnabled) {
          screen = _ShaderOverlay(
            program: loadScanlineProgram(),
            setUniforms: (shader, bounds) {
              shader
                ..setFloat(0, bounds.width)
                ..setFloat(1, bounds.height)
                ..setFloat(2, frameHeight.toDouble());
            },
            child: screen,
          );
        }
        return Center(
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: screen,
          ),
        );
      },
    );
  }
}

/// RGBフィルターの倍率の上限。ネイティブ側の受理範囲（1〜8）に合わせる。
const int maxScreenPower = 8;

/// 表示の大きさ[displaySize]（論理ピクセル）に対するRGBフィルターの倍率。
///
/// 移植元（`native/core/upstream/src/win32/osd_screen.cpp`の
/// `OSD::draw_screen()`）の`dest_pow_x = ceil(draw_screen_width /
/// tmp_width)`と同じ式。移植元は整数の画素数で計算するため、表示の大きさを
/// 整数へ丸めてから割る。
({int x, int y}) screenPowerFor({
  required Size displaySize,
  required int frameWidth,
  required int frameHeight,
}) {
  int power(double display, int frame) {
    if (frame <= 0) {
      return 1;
    }
    final pixels = display.round();
    return ((pixels + frame - 1) ~/ frame).clamp(1, maxScreenPower);
  }

  return (
    x: power(displaySize.width, frameWidth),
    y: power(displaySize.height, frameHeight),
  );
}

/// [program]のロード完了を待ち、完了後は毎フレーム
/// [setUniforms]でuniformを設定した`FragmentShader`を`ShaderMask`へ渡す。
///
/// ロード完了までは`child`をそのまま表示する（効果なし相当）。
class _ShaderOverlay extends StatelessWidget {
  const _ShaderOverlay({
    required this.program,
    required this.setUniforms,
    required this.child,
  });

  final Future<FragmentProgram> program;
  final void Function(FragmentShader shader, Rect bounds) setUniforms;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<FragmentProgram>(
      future: program,
      builder: (context, snapshot) {
        final loaded = snapshot.data;
        if (loaded == null) {
          return child;
        }
        return ShaderMask(
          blendMode: BlendMode.modulate,
          shaderCallback: (bounds) {
            final shader = loaded.fragmentShader();
            setUniforms(shader, bounds);
            return shader;
          },
          child: child,
        );
      },
    );
  }
}
