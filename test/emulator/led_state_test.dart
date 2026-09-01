import 'package:bubi_fm77av40ex/emulator/led_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// vm/fm7/keyboard.cpp の SIG_FM7KEY_LED_STATUS ビット
/// （0x1=INS、0x2=KANA、0x4=CAPS）の変換を検査する（INP-02）。
void main() {
  test('ビットが立っていなければすべて消灯', () {
    final state = LedState.fromBits(0);
    expect(state, const LedState());
  });

  test('各ビットが独立してONへ変換される', () {
    expect(LedState.fromBits(0x1), const LedState(insert: true));
    expect(LedState.fromBits(0x2), const LedState(kana: true));
    expect(LedState.fromBits(0x4), const LedState(caps: true));
  });

  test('複数ビットの組合せを保持する', () {
    expect(
      LedState.fromBits(0x7),
      const LedState(insert: true, kana: true, caps: true),
    );
  });

  test('未知のビットは無視する', () {
    expect(LedState.fromBits(0xf8), const LedState());
  });
}
