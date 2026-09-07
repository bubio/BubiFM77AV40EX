import 'package:bubi_fm77av40ex/features/session/input/kana_key_table.dart';
import 'package:bubi_fm77av40ex/features/session/input/win32_vk.dart';
import 'package:flutter_test/flutter_test.dart';

/// `kana_key_table.dart`の対応表の契約（INP-03）。
///
/// `native/core/upstream/src/vm/fm7/keyboard_tables.h`の
/// `vk_matrix_106`・`standard_key`/`standard_shift_key`・
/// `kana_key`/`kana_shift_key`から手で突き合わせた値なので、代表的な
/// 数点をハードコードして転記ミスを検出できるようにする。
void main() {
  group('ASCII', () {
    test('英字はVK=大文字ASCIIコード、Shiftは大文字のときだけ', () {
      expect(chordForAscii('a'), const KeyChord(0x41));
      expect(chordForAscii('A'), const KeyChord(0x41, shift: true));
      expect(chordForAscii('z'), const KeyChord(0x5a));
      expect(chordForAscii('Z'), const KeyChord(0x5a, shift: true));
    });

    test('数字はVK=ASCIIコード、Shiftで数字行記号になる', () {
      expect(chordForAscii('1'), KeyChord(Win32Vk.digit0 + 1));
      expect(chordForAscii('!'), KeyChord(Win32Vk.digit0 + 1, shift: true));
      expect(chordForAscii('0'), KeyChord(Win32Vk.digit0));
    });

    test('主要記号（JIS配列の対応）', () {
      expect(chordForAscii('-'), KeyChord(Win32Vk.oemMinus));
      expect(chordForAscii('='), KeyChord(Win32Vk.oemMinus, shift: true));
      expect(chordForAscii(';'), KeyChord(Win32Vk.oemPlus));
      expect(chordForAscii('+'), KeyChord(Win32Vk.oemPlus, shift: true));
      expect(chordForAscii(':'), KeyChord(Win32Vk.oem1));
      expect(chordForAscii('*'), KeyChord(Win32Vk.oem1, shift: true));
      expect(chordForAscii('_'), KeyChord(Win32Vk.oem102, shift: true));
    });

    test('改行・タブ・空白', () {
      expect(chordForAscii('\n'), KeyChord(Win32Vk.returnKey));
      expect(chordForAscii('\t'), KeyChord(Win32Vk.tab));
      expect(chordForAscii(' '), KeyChord(Win32Vk.space));
    });

    test('対応がない文字はnull', () {
      expect(chordForAscii('あ'), isNull);
      expect(chordForAscii('漢'), isNull);
    });
  });

  group('カタカナ', () {
    test('清音の代表例', () {
      expect(chordForKana('ア'), isNotNull);
      expect(chordForKana('カ'), KeyChord(Win32Vk.keyA + 19)); // 'T'
      expect(chordForKana('ン'), KeyChord(Win32Vk.keyA + 24)); // 'Y'
    });

    test('濁点・半濁点は独立した文字として対応を持つ', () {
      expect(chordForKana('゛'), KeyChord(Win32Vk.oem3));
      expect(chordForKana('゜'), KeyChord(Win32Vk.oem4));
    });

    test('句読点・中黒・かぎ括弧', () {
      expect(chordForKana('。'), KeyChord(Win32Vk.oemPeriod, shift: true));
      expect(chordForKana('、'), KeyChord(Win32Vk.oemComma, shift: true));
      expect(chordForKana('「'), KeyChord(Win32Vk.oem4, shift: true));
      expect(chordForKana('」'), KeyChord(Win32Vk.oem6, shift: true));
      expect(chordForKana('・'), KeyChord(Win32Vk.oem2, shift: true));
    });

    test('JIS X0201半角カタカナ相当の全63文字すべてに対応がある', () {
      const all =
          '。「」、・ヲァィゥェォャュョッーアイウエオカキクケコサシスセソ'
          'タチツテトナニヌネノハヒフヘホマミムメモヤユヨラリルレロワン゛゜';
      expect(all.length, 63);
      for (final ch in all.characters) {
        expect(chordForKana(ch), isNotNull, reason: '$chは未対応');
      }
    });
  });
}

extension on String {
  Iterable<String> get characters => runes.map(String.fromCharCode);
}
