import 'dart:ui' show Size;

import 'package:bubifm77av40ex/features/display/widgets/emulator_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// RGBフィルターの倍率（VID-04）。移植元の`ceil(表示幅 / 画面幅)`と同じ値に
/// なることを確かめる。
void main() {
  ({int x, int y}) power(double width, double height) => screenPowerFor(
    displaySize: Size(width, height),
    frameWidth: 640,
    frameHeight: 400,
  );

  test('ウィンドウ倍率x1・x2・x3の表示はそれぞれ倍率1・2・3', () {
    expect(power(640, 400), (x: 1, y: 1));
    expect(power(1280, 800), (x: 2, y: 2));
    expect(power(1920, 1200), (x: 3, y: 3));
  });

  test('整数倍でなければ切り上げる', () {
    expect(power(900, 562.5), (x: 2, y: 2));
    expect(power(1281, 801), (x: 3, y: 3));
  });

  test('浮動小数の誤差は整数へ丸めてから割るため切り上げに響かない', () {
    expect(power(1280.0000001, 799.9999999), (x: 2, y: 2));
  });

  test('横と縦は別々に求める', () {
    expect(power(1920, 800), (x: 3, y: 2));
  });

  test('表示が画面より小さくても1、大きすぎても上限で止める', () {
    expect(power(320, 200), (x: 1, y: 1));
    expect(power(640 * 20, 400 * 20), (x: maxScreenPower, y: maxScreenPower));
  });
}
