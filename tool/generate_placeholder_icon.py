#!/usr/bin/env python3
"""暫定アプリアイコン（1024x1024 PNG）を決定的に生成する。

design.md 15.3 の制約に従い、文字・商標・既存キャラクター・細線を含めない。
正式素材が提供されたら assets/branding/app_icon.png を差し替えるだけでよい。

生成手段の記録:
  - 手段: 本スクリプト（Python標準ライブラリのみ、zlib+structでPNGを直接出力）
  - 外部の画像生成モデルやプロンプトは使用していない
  - 図案: 濃紺の角丸背景に、FM77AV系の3面ディスプレイを想起させる
          同心の角丸矩形をオレンジ／白で重ねた抽象図形

使い方:
  python3 tool/generate_placeholder_icon.py assets/branding/app_icon.png
"""

from __future__ import annotations

import struct
import sys
import zlib

SIZE = 1024

BACKGROUND = (0x10, 0x16, 0x2C)
PANEL = (0x1E, 0x2C, 0x52)
ACCENT = (0xF2, 0x8C, 0x28)
HIGHLIGHT = (0xF5, 0xF7, 0xFA)


def rounded_rect_alpha(x: float, y: float, rect, radius: float) -> float:
    """角丸矩形の内側なら1.0、外側なら0.0、境界は被覆率を近似して返す。"""
    left, top, right, bottom = rect
    cx = min(max(x, left + radius), right - radius)
    cy = min(max(y, top + radius), bottom - radius)
    dx = x - cx
    dy = y - cy
    distance = (dx * dx + dy * dy) ** 0.5
    if x < left or x > right or y < top or y > bottom:
        return 0.0
    # 境界1px分で線形にフェードさせ、拡大縮小時のジャギーを抑える。
    return min(max(radius - distance + 0.5, 0.0), 1.0) if radius > 0 else 1.0


def blend(base, layer, alpha: float):
    return tuple(round(b + (l - b) * alpha) for b, l in zip(base, layer))


def render() -> bytes:
    s = SIZE
    outer = (0.0, 0.0, float(s), float(s))
    screen = (s * 0.16, s * 0.22, s * 0.84, s * 0.70)
    band = (s * 0.24, s * 0.30, s * 0.76, s * 0.44)
    base_bar = (s * 0.30, s * 0.78, s * 0.70, s * 0.86)

    rows = bytearray()
    for py in range(s):
        rows.append(0)  # PNG filter type 0
        y = py + 0.5
        for px in range(s):
            x = px + 0.5
            color = BACKGROUND
            alpha_outer = rounded_rect_alpha(x, y, outer, s * 0.22)
            color = blend((0, 0, 0), color, alpha_outer)
            color = blend(color, PANEL, rounded_rect_alpha(x, y, screen, s * 0.06))
            color = blend(color, ACCENT, rounded_rect_alpha(x, y, band, s * 0.03))
            color = blend(color, HIGHLIGHT, rounded_rect_alpha(x, y, base_bar, s * 0.02))
            rows.extend(color)
            rows.append(round(255 * alpha_outer))
    return bytes(rows)


def chunk(tag: bytes, data: bytes) -> bytes:
    return (
        struct.pack('>I', len(data))
        + tag
        + data
        + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


def write_png(path: str) -> None:
    header = struct.pack('>IIBBBBB', SIZE, SIZE, 8, 6, 0, 0, 0)
    payload = zlib.compress(render(), 9)
    with open(path, 'wb') as handle:
        handle.write(b'\x89PNG\r\n\x1a\n')
        handle.write(chunk(b'IHDR', header))
        handle.write(chunk(b'IDAT', payload))
        handle.write(chunk(b'IEND', b''))


if __name__ == '__main__':
    write_png(sys.argv[1] if len(sys.argv) > 1 else 'assets/branding/app_icon.png')
