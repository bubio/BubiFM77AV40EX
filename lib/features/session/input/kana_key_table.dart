import 'win32_vk.dart';

/// 1文字を打つための(VKコード, Shift要否)。
class KeyChord {
  const KeyChord(this.vk, {this.shift = false});

  final int vk;
  final bool shift;

  @override
  bool operator ==(Object other) =>
      other is KeyChord && other.vk == vk && other.shift == shift;

  @override
  int get hashCode => Object.hash(vk, shift);

  @override
  String toString() => 'KeyChord(vk: 0x${vk.toRadixString(16)}, shift: $shift)';
}

/// 自動キー入力（INP-03）が対象にできるASCII文字と、そのVKコード。
///
/// `native/core/upstream/src/vm/fm7/keyboard.cpp`の`KEYBOARD::scan2fmkeycode`
/// は、Shift/KANA/CTRL/GRAPHの状態に応じて`standard_key`/`standard_shift_key`
/// （`keyboard_tables.h:61`・`166`）のどちらかを物理スキャンコードで引き、
/// 得たFM7キーコードをそのままキーバッファへ書く。ホストが送るのは
/// win32仮想キーコードだけであり、`vk_matrix_106`（同17行）がVK⇔物理
/// スキャンコードを結ぶ。英数字・記号キーはこの３表の対応がVKコードの
/// 命名（`Win32Vk.keyA`はASCII大文字と同じ値、`Win32Vk.digit0`はASCII数字と
/// 同じ値）と一致するため、大部分は算術で導ける。JISキーボード固有の
/// 記号キー（oem1〜oem102）だけを`standard_key`/`standard_shift_key`から
/// 手で突き合わせて以下の表にした。
final Map<String, KeyChord> asciiKeyChords = {
  ' ': const KeyChord(Win32Vk.space),
  '\n': const KeyChord(Win32Vk.returnKey),
  '\t': const KeyChord(Win32Vk.tab),
  '\b': const KeyChord(Win32Vk.back),

  // standard_key/standard_shift_key phy 0x02〜0x0a（数字行）。
  '!': const KeyChord(Win32Vk.digit0 + 1, shift: true),
  '"': const KeyChord(Win32Vk.digit0 + 2, shift: true),
  '#': const KeyChord(Win32Vk.digit0 + 3, shift: true),
  r'$': const KeyChord(Win32Vk.digit0 + 4, shift: true),
  '%': const KeyChord(Win32Vk.digit0 + 5, shift: true),
  '&': const KeyChord(Win32Vk.digit0 + 6, shift: true),
  "'": const KeyChord(Win32Vk.digit0 + 7, shift: true),
  '(': const KeyChord(Win32Vk.digit0 + 8, shift: true),
  ')': const KeyChord(Win32Vk.digit0 + 9, shift: true),

  // phy 0x0c〜0x0e。
  '-': const KeyChord(Win32Vk.oemMinus),
  '=': const KeyChord(Win32Vk.oemMinus, shift: true),
  '^': const KeyChord(Win32Vk.oem7),
  '~': const KeyChord(Win32Vk.oem7, shift: true),
  '\\': const KeyChord(Win32Vk.oem5),
  '|': const KeyChord(Win32Vk.oem5, shift: true),

  // phy 0x1b・0x1c・0x29（@、[、]）。
  '@': const KeyChord(Win32Vk.oem3),
  '`': const KeyChord(Win32Vk.oem3, shift: true),
  '[': const KeyChord(Win32Vk.oem4),
  '{': const KeyChord(Win32Vk.oem4, shift: true),
  ']': const KeyChord(Win32Vk.oem6),
  '}': const KeyChord(Win32Vk.oem6, shift: true),

  // phy 0x27・0x28（;+、:*）。
  ';': const KeyChord(Win32Vk.oemPlus),
  '+': const KeyChord(Win32Vk.oemPlus, shift: true),
  ':': const KeyChord(Win32Vk.oem1),
  '*': const KeyChord(Win32Vk.oem1, shift: true),

  // phy 0x31〜0x33（,<  .>  /?）。
  ',': const KeyChord(Win32Vk.oemComma),
  '<': const KeyChord(Win32Vk.oemComma, shift: true),
  '.': const KeyChord(Win32Vk.oemPeriod),
  '>': const KeyChord(Win32Vk.oemPeriod, shift: true),
  '/': const KeyChord(Win32Vk.oem2),
  '?': const KeyChord(Win32Vk.oem2, shift: true),

  // phy 0x34（JISの「ろ」キー相当）。shift側だけが`_`。
  '_': const KeyChord(Win32Vk.oem102, shift: true),
};

KeyChord? _letterOrDigitChord(String ch) {
  final code = ch.codeUnitAt(0);
  if (code >= 0x61 && code <= 0x7a) {
    // a-z: VKは大文字ASCIIと同値（Win32Vk.keyA+n）。
    return KeyChord(code - 0x20);
  }
  if (code >= 0x41 && code <= 0x5a) {
    // A-Z
    return KeyChord(code, shift: true);
  }
  if (code >= 0x30 && code <= 0x39) {
    // 0-9: VKはASCII数字と同値（Win32Vk.digit0+n）。
    return KeyChord(code);
  }
  return null;
}

/// [ch]（1文字）を打つための[KeyChord]。対応がなければnull。
KeyChord? chordForAscii(String ch) =>
    _letterOrDigitChord(ch) ?? asciiKeyChords[ch];

/// 自動キー入力（ローマ字かな変換ON、INP-03）が対象にできる半角カタカナ
/// 相当の文字（内部表現は全角カタカナ・濁点・半濁点のUnicode）と、
/// そのVKコード。
///
/// コアは`kana_pressed`（KANAロック、VK 0x15のトグルで管理、
/// `keyboard.cpp`の`sc == 0x5a`分岐）が真のとき、同じ物理スキャンコードを
/// `kana_key`/`kana_shift_key`（`keyboard_tables.h:532`・`639`）で引き、
/// JIS X0201半角カタカナのバイト値（0xA1〜0xDF）をキーバッファへ書く。
/// この表はその2つの定数表と`vk_matrix_106`を突き合わせて作った、
/// 「全角カタカナ文字→(VK, Shift要否)」の対応である。
final Map<String, KeyChord> kanaKeyChords = {
  '。': const KeyChord(Win32Vk.oemPeriod, shift: true), // 0xA1
  '「': const KeyChord(Win32Vk.oem4, shift: true), // 0xA2
  '」': const KeyChord(Win32Vk.oem6, shift: true), // 0xA3
  '、': const KeyChord(Win32Vk.oemComma, shift: true), // 0xA4
  '・': const KeyChord(Win32Vk.oem2, shift: true), // 0xA5
  'ヲ': const KeyChord(Win32Vk.digit0, shift: true), // 0xA6
  'ァ': const KeyChord(Win32Vk.digit0 + 3, shift: true), // 0xA7
  'ィ': const KeyChord(Win32Vk.keyA + 4, shift: true), // 0xA8 ('E')
  'ゥ': const KeyChord(Win32Vk.digit0 + 4, shift: true), // 0xA9
  'ェ': const KeyChord(Win32Vk.digit0 + 5, shift: true), // 0xAA
  'ォ': const KeyChord(Win32Vk.digit0 + 6, shift: true), // 0xAB
  'ャ': const KeyChord(Win32Vk.digit0 + 7, shift: true), // 0xAC
  'ュ': const KeyChord(Win32Vk.digit0 + 8, shift: true), // 0xAD
  'ョ': const KeyChord(Win32Vk.digit0 + 9, shift: true), // 0xAE
  'ッ': const KeyChord(Win32Vk.keyA + 25, shift: true), // 0xAF ('Z')
  'ー': const KeyChord(Win32Vk.oem5), // 0xB0
  'ア': const KeyChord(Win32Vk.digit0 + 3), // 0xB1
  'イ': const KeyChord(Win32Vk.keyA + 4), // 0xB2 ('E')
  'ウ': const KeyChord(Win32Vk.digit0 + 4), // 0xB3
  'エ': const KeyChord(Win32Vk.digit0 + 5), // 0xB4
  'オ': const KeyChord(Win32Vk.digit0 + 6), // 0xB5
  'カ': const KeyChord(Win32Vk.keyA + 19), // 0xB6 ('T')
  'キ': const KeyChord(Win32Vk.keyA + 6), // 0xB7 ('G')
  'ク': const KeyChord(Win32Vk.keyA + 7), // 0xB8 ('H')
  'ケ': const KeyChord(Win32Vk.oem1), // 0xB9
  'コ': const KeyChord(Win32Vk.keyA + 1), // 0xBA ('B')
  'サ': const KeyChord(Win32Vk.keyA + 23), // 0xBB ('X')
  'シ': const KeyChord(Win32Vk.keyA + 3), // 0xBC ('D')
  'ス': const KeyChord(Win32Vk.keyA + 17), // 0xBD ('R')
  'セ': const KeyChord(Win32Vk.keyA + 15), // 0xBE ('P')
  'ソ': const KeyChord(Win32Vk.keyA + 2), // 0xBF ('C')
  'タ': const KeyChord(Win32Vk.keyA + 16), // 0xC0 ('Q')
  'チ': const KeyChord(Win32Vk.keyA + 0), // 0xC1 ('A')
  'ツ': const KeyChord(Win32Vk.keyA + 25), // 0xC2 ('Z')
  'テ': const KeyChord(Win32Vk.keyA + 22), // 0xC3 ('W')
  'ト': const KeyChord(Win32Vk.keyA + 18), // 0xC4 ('S')
  'ナ': const KeyChord(Win32Vk.keyA + 20), // 0xC5 ('U')
  'ニ': const KeyChord(Win32Vk.keyA + 8), // 0xC6 ('I')
  'ヌ': const KeyChord(Win32Vk.digit0 + 1), // 0xC7
  'ネ': const KeyChord(Win32Vk.oemComma), // 0xC8
  'ノ': const KeyChord(Win32Vk.keyA + 10), // 0xC9 ('K')
  'ハ': const KeyChord(Win32Vk.keyA + 5), // 0xCA ('F')
  'ヒ': const KeyChord(Win32Vk.keyA + 21), // 0xCB ('V')
  'フ': const KeyChord(Win32Vk.digit0 + 2), // 0xCC
  'ヘ': const KeyChord(Win32Vk.oem7), // 0xCD
  'ホ': const KeyChord(Win32Vk.oemMinus), // 0xCE
  'マ': const KeyChord(Win32Vk.keyA + 9), // 0xCF ('J')
  'ミ': const KeyChord(Win32Vk.keyA + 13), // 0xD0 ('N')
  'ム': const KeyChord(Win32Vk.oem6), // 0xD1
  'メ': const KeyChord(Win32Vk.oem2), // 0xD2
  'モ': const KeyChord(Win32Vk.keyA + 12), // 0xD3 ('M')
  'ヤ': const KeyChord(Win32Vk.digit0 + 7), // 0xD4
  'ユ': const KeyChord(Win32Vk.digit0 + 8), // 0xD5
  'ヨ': const KeyChord(Win32Vk.digit0 + 9), // 0xD6
  'ラ': const KeyChord(Win32Vk.keyA + 14), // 0xD7 ('O')
  'リ': const KeyChord(Win32Vk.keyA + 11), // 0xD8 ('L')
  'ル': const KeyChord(Win32Vk.oemPeriod), // 0xD9
  'レ': const KeyChord(Win32Vk.oemPlus), // 0xDA
  'ロ': const KeyChord(Win32Vk.oem102), // 0xDB
  'ワ': const KeyChord(Win32Vk.digit0), // 0xDC
  'ン': const KeyChord(Win32Vk.keyA + 24), // 0xDD ('Y')
  '゛': const KeyChord(Win32Vk.oem3), // 0xDE 濁点
  '゜': const KeyChord(Win32Vk.oem4), // 0xDF 半濁点
};

/// [ch]（1文字、全角カタカナまたは濁点・半濁点）を打つための[KeyChord]。
/// 対応がなければnull。
KeyChord? chordForKana(String ch) => kanaKeyChords[ch];
