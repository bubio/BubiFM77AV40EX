import 'dart:ui' show FragmentProgram, FragmentShader;

import 'package:flutter/widgets.dart';

import '../screen_filter.dart';
import '../screen_fit.dart';
import '../shader_filters.dart';

/// コアの画面を出す。
///
/// 画素はネイティブ側がTextureへ直接書き込むため、ここを通らない
/// （design.md 16.1）。このWidgetが決めるのは置き方と、走査線・
/// RGBフィルター（VID-04）の重ね掛けである。フィルターはテクスチャの
/// 画素を読まない位置だけのshaderのため、`ShaderMask`
/// （`BlendMode.modulate`）で下地へ掛け合わせる。
class EmulatorScreen extends StatelessWidget {
  const EmulatorScreen({
    required this.textureId,
    required this.frameWidth,
    required this.frameHeight,
    this.fit = ScreenFit.aspect,
    this.scanlineEnabled = false,
    this.filter = HostScreenFilter.none,
    super.key,
  });

  final int textureId;
  final int frameWidth;
  final int frameHeight;
  final ScreenFit fit;
  final bool scanlineEnabled;
  final HostScreenFilter filter;

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
        Widget screen = Texture(textureId: textureId);
        if (filter == HostScreenFilter.rgb) {
          screen = _ShaderOverlay(
            program: loadRgbFilterProgram(),
            setUniforms: (shader, bounds) {
              shader
                ..setFloat(0, bounds.width)
                ..setFloat(1, bounds.height)
                ..setFloat(2, frameWidth.toDouble());
            },
            child: screen,
          );
        }
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

/// [program]のロード完了を待ち、完了後は毎フレーム
/// [setUniforms]でuniformを設定した`FragmentShader`を`ShaderMask`へ渡す。
///
/// ロード完了までは`child`をそのまま表示する（フィルターなし相当）。
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
