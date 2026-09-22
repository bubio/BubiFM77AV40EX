import 'package:bubifm77av40ex/features/session/input/auto_key_engine.dart';
import 'package:bubifm77av40ex/features/session/input/win32_vk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes.dart';

/// [AutoKeyEngine]（INP-03）のタイミングと状態遷移。
///
/// タイマーは`fake_async`で仮想時間を進めて検証する
/// （`emulator_controller_test.dart`のView/Core FPS試験と同じ手法）。
void main() {
  test('1文字ずつdown→up→次のdownの順に、既定タイミングで送られる', () {
    fakeAsync((async) {
      final session = FakeEmulatorSession();
      final engine = AutoKeyEngine();

      engine.run(
        session,
        'ab',
        romajiToKana: false,
        initialKanaLock: false,
        initialCapsLock: false,
      );
      async.elapse(const Duration(milliseconds: 400));

      expect(session.keyEvents, [0x41, -0x41, 0x42, -0x42]);
      expect(engine.isRunning, isFalse);
    });
  });

  test('KANA区間の境界だけでロックをトグルし、終了時に元へ戻す', () {
    fakeAsync((async) {
      final session = FakeEmulatorSession();
      final engine = AutoKeyEngine();

      // 'a'（ASCII）→ 'ア'（カタカナ）の順。KANAロックは開始時OFF。
      engine.run(
        session,
        'aア',
        romajiToKana: false,
        initialKanaLock: false,
        initialCapsLock: false,
      );
      async.elapse(const Duration(milliseconds: 800));

      expect(session.keyEvents, [
        0x41, -0x41, // 'a'
        Win32Vk.kana, -Win32Vk.kana, // KANAロックON
        Win32Vk.digit0 + 3, -(Win32Vk.digit0 + 3), // 'ア'
        Win32Vk.kana, -Win32Vk.kana, // 終了時に元(OFF)へ戻す
      ]);
    });
  });

  test('開始時すでにKANAロックがONなら、かな文字の前後でトグルしない', () {
    fakeAsync((async) {
      final session = FakeEmulatorSession();
      final engine = AutoKeyEngine();

      engine.run(
        session,
        'ア',
        romajiToKana: false,
        initialKanaLock: true,
        initialCapsLock: false,
      );
      async.elapse(const Duration(milliseconds: 400));

      expect(session.keyEvents, [Win32Vk.digit0 + 3, -(Win32Vk.digit0 + 3)]);
    });
  });

  test('CAPSロックがONのときは大文字を出すためにShiftを送らない（CAPS反転の相殺）', () {
    fakeAsync((async) {
      final session = FakeEmulatorSession();
      final engine = AutoKeyEngine();

      engine.run(
        session,
        'A',
        romajiToKana: false,
        initialKanaLock: false,
        initialCapsLock: true,
      );
      async.elapse(const Duration(milliseconds: 400));

      // Shift（0xa0）を送らずVK 0x41だけをdown/upする。
      expect(session.keyEvents, [0x41, -0x41]);
    });
  });

  test('CAPSロックがONのときは小文字を出すためにShiftを送る（CAPS反転の相殺）', () {
    fakeAsync((async) {
      final session = FakeEmulatorSession();
      final engine = AutoKeyEngine();

      engine.run(
        session,
        'a',
        romajiToKana: false,
        initialKanaLock: false,
        initialCapsLock: true,
      );
      async.elapse(const Duration(milliseconds: 400));

      // Shiftは本体キーを挟む（keyUpは本体キーのupの直後）。
      expect(session.keyEvents, [Win32Vk.lshift, 0x41, -0x41, -Win32Vk.lshift]);
    });
  });

  test('CAPSロックはASCII英字以外（数字・カタカナ）には影響しない', () {
    fakeAsync((async) {
      final session = FakeEmulatorSession();
      final engine = AutoKeyEngine();

      engine.run(
        session,
        '1ア',
        romajiToKana: false,
        initialKanaLock: false,
        initialCapsLock: true,
      );
      async.elapse(const Duration(milliseconds: 800));

      expect(session.keyEvents, [
        Win32Vk.digit0 + 1,
        -(Win32Vk.digit0 + 1),
        Win32Vk.kana,
        -Win32Vk.kana,
        Win32Vk.digit0 + 3,
        -(Win32Vk.digit0 + 3),
        Win32Vk.kana,
        -Win32Vk.kana,
      ]);
    });
  });

  test('cancel()は保留中のキーをupしてから停止し、KANAロックを元へ戻す', () {
    fakeAsync((async) {
      final session = FakeEmulatorSession();
      final engine = AutoKeyEngine();

      engine.run(
        session,
        'アイ',
        romajiToKana: false,
        initialKanaLock: false,
        initialCapsLock: false,
      );
      // 最初の文字のdown直後（up前）まで進める。
      async.elapse(const Duration(milliseconds: 10));
      expect(engine.isRunning, isTrue);

      engine.cancel();
      // cancel()はタイマー発火まで反映されないため、次のステップ分だけ進める。
      async.elapse(const Duration(milliseconds: 200));

      expect(engine.isRunning, isFalse);
      // KANAロックON→「ア」のdown→cancel由来のup→KANAロックOFFへ復帰。
      // 2文字目「イ」は送られていない。
      expect(session.keyEvents, [
        Win32Vk.kana,
        -Win32Vk.kana,
        Win32Vk.digit0 + 3,
        -(Win32Vk.digit0 + 3),
        Win32Vk.kana,
        -Win32Vk.kana,
      ]);
    });
  });

  test('打てる文字が1つもなければ何もしない', () {
    fakeAsync((async) {
      final session = FakeEmulatorSession();
      final engine = AutoKeyEngine();

      engine.run(
        session,
        '漢字',
        romajiToKana: false,
        initialKanaLock: false,
        initialCapsLock: false,
      );
      async.elapse(const Duration(milliseconds: 100));

      expect(session.keyEvents, isEmpty);
      expect(engine.isRunning, isFalse);
    });
  });

  test('実行中に2回目のrun()を呼んでも無視する', () {
    fakeAsync((async) {
      final session = FakeEmulatorSession();
      final engine = AutoKeyEngine();

      engine.run(
        session,
        'ab',
        romajiToKana: false,
        initialKanaLock: false,
        initialCapsLock: false,
      );
      async.elapse(const Duration(milliseconds: 10));
      engine.run(
        session,
        'cd',
        romajiToKana: false,
        initialKanaLock: false,
        initialCapsLock: false,
      );
      async.elapse(const Duration(milliseconds: 400));

      // 'c'/'d'（0x43/0x44）は送られていない。
      expect(session.keyEvents, [0x41, -0x41, 0x42, -0x42]);
    });
  });

  test('一時停止中は打鍵を進めず、再開後に段取りの待ち時間を数え直す', () {
    fakeAsync((async) {
      final session = FakeEmulatorSession();
      final engine = AutoKeyEngine();

      engine.run(
        session,
        'ab',
        romajiToKana: false,
        initialKanaLock: false,
        initialCapsLock: false,
      );
      async.elapse(const Duration(milliseconds: 10));
      expect(session.keyEvents, [0x41]);

      engine.setPaused(true);
      async.elapse(const Duration(seconds: 1));
      // 押下中の'a'は解放されず、次の文字へも進まない。
      expect(session.keyEvents, [0x41]);

      engine.setPaused(false);
      // 再開直後は押下の待ち時間（83ms）を最初から数え直す。
      async.elapse(const Duration(milliseconds: 50));
      expect(session.keyEvents, [0x41]);
      async.elapse(const Duration(milliseconds: 400));
      expect(session.keyEvents, [0x41, -0x41, 0x42, -0x42]);
      expect(engine.isRunning, isFalse);
    });
  });

  test('一時停止中のcancel()は保留中のキーを離して終わる', () {
    fakeAsync((async) {
      final session = FakeEmulatorSession();
      final engine = AutoKeyEngine();

      engine.run(
        session,
        'ab',
        romajiToKana: false,
        initialKanaLock: false,
        initialCapsLock: false,
      );
      async.elapse(const Duration(milliseconds: 10));
      engine.setPaused(true);
      async.elapse(const Duration(milliseconds: 200));

      var cancelled = false;
      engine.cancel().then((_) => cancelled = true);
      async.elapse(const Duration(milliseconds: 200));

      expect(cancelled, isTrue);
      expect(session.keyEvents, [0x41, -0x41]);
      expect(engine.isRunning, isFalse);
    });
  });
}
