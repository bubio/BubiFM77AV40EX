/// [EmulatorSession.setJoystickState]へ渡すビット定義（M3 INP-04）。
///
/// コア（`vm/fm7/joystick.cpp`）のactive-high規約（1が押下状態）に合わせる。
/// ネイティブ境界（`lib/platform/core_ffi/`）だけがFFIの生の整数値を扱うため
/// （design.md 3.1、16.1）、この定数はドメイン層（`lib/emulator/`）に置く。
abstract final class JoystickBit {
  static const int up = 0x01;
  static const int down = 0x02;
  static const int left = 0x04;
  static const int right = 0x08;
  static const int button1 = 0x10;
  static const int button2 = 0x20;
}
