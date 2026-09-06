// ホスト側のRGBフィルター効果（VID-04、design.md 16.1）。
//
// コアはRGBサブピクセル効果を持たないため（Win32限定の
// apply_rgb_filter_to_screen_buffer系はこのブリッジに繋がっていない）、
// ホスト側で1論理画素をR/G/Bの3分割へ強調する。テクスチャの画素は読まず、
// 呼び出し側が BlendMode.modulate の ShaderMask として使う。
#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uSourceWidth;

out vec4 fragColor;

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  float columnWidth = max(uSize.x / max(uSourceWidth, 1.0), 1.0) / 3.0;
  float triad = mod(floor(fragCoord.x / columnWidth), 3.0);
  float dim = 0.55;
  vec3 mask = vec3(dim, dim, dim);
  if (triad < 1.0) {
    mask.r = 1.0;
  } else if (triad < 2.0) {
    mask.g = 1.0;
  } else {
    mask.b = 1.0;
  }
  fragColor = vec4(mask, 1.0);
}
