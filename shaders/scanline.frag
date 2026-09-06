// ホスト側の走査線効果（VID-04、design.md 16.1）。
//
// コアは実行時に走査線数を変えないため（native/bridge/osd/sdl/
// osd_screen.cpp の set_vm_screen_lines() は明示的no-op）、この効果は
// テクスチャの画素を読まず、位置だけで暗い縞を掛け合わせる
// （呼び出し側は BlendMode.modulate の ShaderMask で使う）。
#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uSourceHeight;

out vec4 fragColor;

void main() {
  vec2 fragCoord = FlutterFragCoord().xy;
  float rowHeight = max(uSize.y / max(uSourceHeight, 1.0), 1.0);
  float row = floor(fragCoord.y / rowHeight);
  float isDarkRow = mod(row, 2.0);
  float shade = mix(1.0, 0.55, isDarkRow);
  fragColor = vec4(shade, shade, shade, 1.0);
}
