/// win32仮想キーコード。
///
/// コアの`vk_matrix_106`（vm/fm7/keyboard_tables.h）がこの値を走査コードへ
/// 変換するため、ホストOSに関わらずwin32の値を送る（compat/vkcodes.h）。
abstract final class Win32Vk {
  static const int back = 0x08;
  static const int tab = 0x09;
  static const int returnKey = 0x0d;
  static const int shift = 0x10;
  static const int control = 0x11;
  static const int menu = 0x12;
  static const int capital = 0x14;
  static const int kana = 0x15;
  static const int kanji = 0x19;
  static const int convert = 0x1c;
  static const int nonConvert = 0x1d;
  static const int escape = 0x1b;
  static const int space = 0x20;
  static const int prior = 0x21;
  static const int next = 0x22;
  static const int end = 0x23;
  static const int home = 0x24;
  static const int left = 0x25;
  static const int up = 0x26;
  static const int right = 0x27;
  static const int down = 0x28;
  static const int insert = 0x2d;
  static const int delete = 0x2e;

  // '0'..'9' は ASCII と同じ 0x30..0x39。
  static const int digit0 = 0x30;
  // 'A'..'Z' は ASCII と同じ 0x41..0x5a。
  static const int keyA = 0x41;

  static const int lwin = 0x5b;
  static const int rwin = 0x5c;

  static const int numpad0 = 0x60;
  static const int multiply = 0x6a;
  static const int add = 0x6b;
  static const int subtract = 0x6d;
  static const int decimal = 0x6e;
  static const int divide = 0x6f;

  static const int f1 = 0x70;

  static const int numLock = 0x90;
  static const int scroll = 0x91;

  static const int lshift = 0xa0;
  static const int rshift = 0xa1;
  static const int lcontrol = 0xa2;
  static const int rcontrol = 0xa3;
  static const int lmenu = 0xa4;
  static const int rmenu = 0xa5;

  static const int oem1 = 0xba; // ; :
  static const int oemPlus = 0xbb; // = +
  static const int oemComma = 0xbc; // , <
  static const int oemMinus = 0xbd; // - _
  static const int oemPeriod = 0xbe; // . >
  static const int oem2 = 0xbf; // / ?
  static const int oem3 = 0xc0; // ` ~

  static const int oem4 = 0xdb; // [ {
  static const int oem5 = 0xdc; // \ |
  static const int oem6 = 0xdd; // ] }
  static const int oem7 = 0xde; // ' "
  static const int oem102 = 0xe2; // 102キー配列の追加キー
}
