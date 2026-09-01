/// キーボードLEDの意味づけ（INP-02）。
///
/// コアの `get_led_status()` が返すビットは vm/fm7/keyboard.cpp の
/// `SIG_FM7KEY_LED_STATUS` が決めており、0x1=INS、0x2=KANA、0x4=CAPS。
class LedState {
  const LedState({this.insert = false, this.kana = false, this.caps = false});

  factory LedState.fromBits(int bits) => LedState(
    insert: (bits & 0x1) != 0,
    kana: (bits & 0x2) != 0,
    caps: (bits & 0x4) != 0,
  );

  final bool insert;
  final bool kana;
  final bool caps;

  @override
  bool operator ==(Object other) =>
      other is LedState &&
      other.insert == insert &&
      other.kana == kana &&
      other.caps == caps;

  @override
  int get hashCode => Object.hash(insert, kana, caps);
}
