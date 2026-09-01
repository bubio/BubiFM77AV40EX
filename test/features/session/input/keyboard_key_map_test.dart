import 'package:bubi_fm77av40ex/features/session/input/keyboard_key_map.dart';
import 'package:bubi_fm77av40ex/features/session/input/win32_vk.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// physical keyからwin32仮想キーコードへの変換を検査する（INP-01）。
///
/// コアが要求するのはwin32のVK値であり（compat/vkcodes.h、
/// vm/fm7/keyboard_tables.h）、ここではその値そのものを比較する。
void main() {
  group('physical keyの対応', () {
    test('アルファベットはA=0x41を起点に並ぶ', () {
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.keyA),
        Win32Vk.keyA,
      );
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.keyZ),
        Win32Vk.keyA + 25,
      );
    });

    test('数字キーは物理位置どおり0..9になる', () {
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.digit0),
        Win32Vk.digit0,
      );
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.digit1),
        Win32Vk.digit0 + 1,
      );
    });

    test('ファンクションキーはF1=0x70を起点に並ぶ', () {
      expect(vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.f1), Win32Vk.f1);
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.f10),
        Win32Vk.f1 + 9,
      );
    });

    test('左右のシフト、コントロール、オルトを区別する', () {
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.shiftLeft),
        Win32Vk.lshift,
      );
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.shiftRight),
        Win32Vk.rshift,
      );
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.controlLeft),
        Win32Vk.lcontrol,
      );
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.controlRight),
        Win32Vk.rcontrol,
      );
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.altLeft),
        Win32Vk.lmenu,
      );
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.altRight),
        Win32Vk.rmenu,
      );
    });

    test('JIS配列固有キーはUS配列と衝突しない', () {
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.kanaMode),
        Win32Vk.kana,
      );
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.convert),
        Win32Vk.convert,
      );
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.nonConvert),
        Win32Vk.nonConvert,
      );
    });

    test('編集キーとナビゲーションキーを対応付ける', () {
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.insert),
        Win32Vk.insert,
      );
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.delete),
        Win32Vk.delete,
      );
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.arrowUp),
        Win32Vk.up,
      );
      expect(
        vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.pageUp),
        Win32Vk.prior,
      );
    });
  });

  group('logical keyによる補い', () {
    test('physical keyが対応表にない場合はlogical keyへ落ちる', () {
      expect(
        vkFromKeyEvent(
          physicalKey: PhysicalKeyboardKey.fn,
          logicalKey: LogicalKeyboardKey.tab,
        ),
        Win32Vk.tab,
      );
    });

    test('physical keyが見つかればlogical keyより優先する', () {
      expect(
        vkFromKeyEvent(
          physicalKey: PhysicalKeyboardKey.keyA,
          logicalKey: LogicalKeyboardKey.tab,
        ),
        Win32Vk.keyA,
      );
    });

    test('どちらにも対応がなければnullを返す', () {
      expect(vkFromKeyEvent(physicalKey: PhysicalKeyboardKey.fn), isNull);
    });
  });
}
