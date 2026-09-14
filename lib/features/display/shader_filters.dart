import 'dart:ui' show FragmentProgram;

/// 走査線のshaderをプロセス内で一度だけ読み込む（VID-04、design.md 16.1）。
///
/// 位置だけで下地を掛け合わせる`ShaderMask`用のshaderであり、
/// テクスチャの画素は読まない。
Future<FragmentProgram>? _scanlineProgram;

Future<FragmentProgram> loadScanlineProgram() {
  return _scanlineProgram ??= FragmentProgram.fromAsset(
    'shaders/scanline.frag',
  );
}
