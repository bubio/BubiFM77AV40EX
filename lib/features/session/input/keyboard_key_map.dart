import 'package:flutter/services.dart';

import 'win32_vk.dart';

/// PhysicalKeyboardKeyからwin32仮想キーコードへの変換（INP-01）。
///
/// design.md 8「キーボードはFlutterのphysical keyを基準にFM77AVキーコードへ
/// 変換し、OS配列差はlogical keyで補助する」に従う。物理位置を基準にするため
/// US配列を前提に固定した対応にする。JIS配列固有のキー（変換／無変換／
/// カナ／円記号／ろ）はUSBのHID Usageで独立した物理キーとして届くため、
/// この対応だけで両配列を扱える。
final Map<PhysicalKeyboardKey, int> _physicalKeyToVk = {
  PhysicalKeyboardKey.keyA: Win32Vk.keyA + 0,
  PhysicalKeyboardKey.keyB: Win32Vk.keyA + 1,
  PhysicalKeyboardKey.keyC: Win32Vk.keyA + 2,
  PhysicalKeyboardKey.keyD: Win32Vk.keyA + 3,
  PhysicalKeyboardKey.keyE: Win32Vk.keyA + 4,
  PhysicalKeyboardKey.keyF: Win32Vk.keyA + 5,
  PhysicalKeyboardKey.keyG: Win32Vk.keyA + 6,
  PhysicalKeyboardKey.keyH: Win32Vk.keyA + 7,
  PhysicalKeyboardKey.keyI: Win32Vk.keyA + 8,
  PhysicalKeyboardKey.keyJ: Win32Vk.keyA + 9,
  PhysicalKeyboardKey.keyK: Win32Vk.keyA + 10,
  PhysicalKeyboardKey.keyL: Win32Vk.keyA + 11,
  PhysicalKeyboardKey.keyM: Win32Vk.keyA + 12,
  PhysicalKeyboardKey.keyN: Win32Vk.keyA + 13,
  PhysicalKeyboardKey.keyO: Win32Vk.keyA + 14,
  PhysicalKeyboardKey.keyP: Win32Vk.keyA + 15,
  PhysicalKeyboardKey.keyQ: Win32Vk.keyA + 16,
  PhysicalKeyboardKey.keyR: Win32Vk.keyA + 17,
  PhysicalKeyboardKey.keyS: Win32Vk.keyA + 18,
  PhysicalKeyboardKey.keyT: Win32Vk.keyA + 19,
  PhysicalKeyboardKey.keyU: Win32Vk.keyA + 20,
  PhysicalKeyboardKey.keyV: Win32Vk.keyA + 21,
  PhysicalKeyboardKey.keyW: Win32Vk.keyA + 22,
  PhysicalKeyboardKey.keyX: Win32Vk.keyA + 23,
  PhysicalKeyboardKey.keyY: Win32Vk.keyA + 24,
  PhysicalKeyboardKey.keyZ: Win32Vk.keyA + 25,

  PhysicalKeyboardKey.digit0: Win32Vk.digit0 + 0,
  PhysicalKeyboardKey.digit1: Win32Vk.digit0 + 1,
  PhysicalKeyboardKey.digit2: Win32Vk.digit0 + 2,
  PhysicalKeyboardKey.digit3: Win32Vk.digit0 + 3,
  PhysicalKeyboardKey.digit4: Win32Vk.digit0 + 4,
  PhysicalKeyboardKey.digit5: Win32Vk.digit0 + 5,
  PhysicalKeyboardKey.digit6: Win32Vk.digit0 + 6,
  PhysicalKeyboardKey.digit7: Win32Vk.digit0 + 7,
  PhysicalKeyboardKey.digit8: Win32Vk.digit0 + 8,
  PhysicalKeyboardKey.digit9: Win32Vk.digit0 + 9,

  PhysicalKeyboardKey.f1: Win32Vk.f1 + 0,
  PhysicalKeyboardKey.f2: Win32Vk.f1 + 1,
  PhysicalKeyboardKey.f3: Win32Vk.f1 + 2,
  PhysicalKeyboardKey.f4: Win32Vk.f1 + 3,
  PhysicalKeyboardKey.f5: Win32Vk.f1 + 4,
  PhysicalKeyboardKey.f6: Win32Vk.f1 + 5,
  PhysicalKeyboardKey.f7: Win32Vk.f1 + 6,
  PhysicalKeyboardKey.f8: Win32Vk.f1 + 7,
  PhysicalKeyboardKey.f9: Win32Vk.f1 + 8,
  PhysicalKeyboardKey.f10: Win32Vk.f1 + 9,

  PhysicalKeyboardKey.numpad0: Win32Vk.numpad0 + 0,
  PhysicalKeyboardKey.numpad1: Win32Vk.numpad0 + 1,
  PhysicalKeyboardKey.numpad2: Win32Vk.numpad0 + 2,
  PhysicalKeyboardKey.numpad3: Win32Vk.numpad0 + 3,
  PhysicalKeyboardKey.numpad4: Win32Vk.numpad0 + 4,
  PhysicalKeyboardKey.numpad5: Win32Vk.numpad0 + 5,
  PhysicalKeyboardKey.numpad6: Win32Vk.numpad0 + 6,
  PhysicalKeyboardKey.numpad7: Win32Vk.numpad0 + 7,
  PhysicalKeyboardKey.numpad8: Win32Vk.numpad0 + 8,
  PhysicalKeyboardKey.numpad9: Win32Vk.numpad0 + 9,
  PhysicalKeyboardKey.numpadMultiply: Win32Vk.multiply,
  PhysicalKeyboardKey.numpadAdd: Win32Vk.add,
  PhysicalKeyboardKey.numpadSubtract: Win32Vk.subtract,
  PhysicalKeyboardKey.numpadDecimal: Win32Vk.decimal,
  PhysicalKeyboardKey.numpadDivide: Win32Vk.divide,
  PhysicalKeyboardKey.numpadEnter: Win32Vk.returnKey,

  PhysicalKeyboardKey.backspace: Win32Vk.back,
  PhysicalKeyboardKey.tab: Win32Vk.tab,
  PhysicalKeyboardKey.enter: Win32Vk.returnKey,
  PhysicalKeyboardKey.escape: Win32Vk.escape,
  PhysicalKeyboardKey.space: Win32Vk.space,
  PhysicalKeyboardKey.capsLock: Win32Vk.capital,
  PhysicalKeyboardKey.numLock: Win32Vk.numLock,
  PhysicalKeyboardKey.scrollLock: Win32Vk.scroll,

  PhysicalKeyboardKey.pageUp: Win32Vk.prior,
  PhysicalKeyboardKey.pageDown: Win32Vk.next,
  PhysicalKeyboardKey.end: Win32Vk.end,
  PhysicalKeyboardKey.home: Win32Vk.home,
  PhysicalKeyboardKey.arrowLeft: Win32Vk.left,
  PhysicalKeyboardKey.arrowUp: Win32Vk.up,
  PhysicalKeyboardKey.arrowRight: Win32Vk.right,
  PhysicalKeyboardKey.arrowDown: Win32Vk.down,
  PhysicalKeyboardKey.insert: Win32Vk.insert,
  PhysicalKeyboardKey.delete: Win32Vk.delete,

  PhysicalKeyboardKey.controlLeft: Win32Vk.lcontrol,
  PhysicalKeyboardKey.controlRight: Win32Vk.rcontrol,
  PhysicalKeyboardKey.shiftLeft: Win32Vk.lshift,
  PhysicalKeyboardKey.shiftRight: Win32Vk.rshift,
  PhysicalKeyboardKey.altLeft: Win32Vk.lmenu,
  PhysicalKeyboardKey.altRight: Win32Vk.rmenu,
  PhysicalKeyboardKey.metaLeft: Win32Vk.lwin,
  PhysicalKeyboardKey.metaRight: Win32Vk.rwin,

  PhysicalKeyboardKey.minus: Win32Vk.oemMinus,
  PhysicalKeyboardKey.equal: Win32Vk.oemPlus,
  PhysicalKeyboardKey.bracketLeft: Win32Vk.oem4,
  PhysicalKeyboardKey.bracketRight: Win32Vk.oem6,
  PhysicalKeyboardKey.backslash: Win32Vk.oem5,
  PhysicalKeyboardKey.semicolon: Win32Vk.oem1,
  PhysicalKeyboardKey.quote: Win32Vk.oem7,
  PhysicalKeyboardKey.backquote: Win32Vk.oem3,
  PhysicalKeyboardKey.comma: Win32Vk.oemComma,
  PhysicalKeyboardKey.period: Win32Vk.oemPeriod,
  PhysicalKeyboardKey.slash: Win32Vk.oem2,
  PhysicalKeyboardKey.intlBackslash: Win32Vk.oem102,

  // JIS配列固有。ISO/JISキーボードだけが送ってくる物理キーなので、
  // US配列と衝突しない。
  PhysicalKeyboardKey.kanaMode: Win32Vk.kana,
  PhysicalKeyboardKey.convert: Win32Vk.convert,
  PhysicalKeyboardKey.nonConvert: Win32Vk.nonConvert,
  PhysicalKeyboardKey.intlRo: Win32Vk.oem102,
  PhysicalKeyboardKey.intlYen: Win32Vk.oem5,
  PhysicalKeyboardKey.lang1: Win32Vk.kanji,
  PhysicalKeyboardKey.lang2: Win32Vk.kanji,
};

/// physical keyだけでは判別できない場合の補い（design.md 8）。
///
/// USB HID Usageの取得に失敗した一部環境向けの保険で、通常経路では
/// physical keyの対応表だけで足りる。
final Map<LogicalKeyboardKey, int> _logicalKeyToVk = {
  LogicalKeyboardKey.controlLeft: Win32Vk.lcontrol,
  LogicalKeyboardKey.controlRight: Win32Vk.rcontrol,
  LogicalKeyboardKey.shiftLeft: Win32Vk.lshift,
  LogicalKeyboardKey.shiftRight: Win32Vk.rshift,
  LogicalKeyboardKey.altLeft: Win32Vk.lmenu,
  LogicalKeyboardKey.altRight: Win32Vk.rmenu,
  LogicalKeyboardKey.metaLeft: Win32Vk.lwin,
  LogicalKeyboardKey.metaRight: Win32Vk.rwin,
  LogicalKeyboardKey.tab: Win32Vk.tab,
  LogicalKeyboardKey.enter: Win32Vk.returnKey,
  LogicalKeyboardKey.escape: Win32Vk.escape,
  LogicalKeyboardKey.space: Win32Vk.space,
  LogicalKeyboardKey.backspace: Win32Vk.back,
  LogicalKeyboardKey.arrowLeft: Win32Vk.left,
  LogicalKeyboardKey.arrowUp: Win32Vk.up,
  LogicalKeyboardKey.arrowRight: Win32Vk.right,
  LogicalKeyboardKey.arrowDown: Win32Vk.down,
};

/// [physicalKey]をwin32仮想キーコードへ変換する。対応がなければnull。
///
/// physical keyでの対応を優先し、取得できなかった場合だけ[logicalKey]を
/// 使う（design.md 8「OS配列差はlogical keyで補助する」）。
int? vkFromKeyEvent({
  required PhysicalKeyboardKey physicalKey,
  LogicalKeyboardKey? logicalKey,
}) {
  final byPhysical = _physicalKeyToVk[physicalKey];
  if (byPhysical != null) {
    return byPhysical;
  }
  if (logicalKey == null) {
    return null;
  }
  return _logicalKeyToVk[logicalKey];
}
