import 'dart:async';

import '../../../emulator/emulator_session.dart';
import 'kana_key_table.dart';
import 'romaji_to_kana.dart';
import 'win32_vk.dart';

/// 1文字を打つための操作（必要なKANAロック状態を含む）。
///
/// 実際にKANAロックをトグルするかどうかは、送出時点の実機の状態
/// （前のステップまでに何を送ったかではなく、開始時の実状態から積み上げた
/// 現在値）と[needsKana]を比べて[AutoKeyEngine.run]が決める。ここでは
/// 「この文字を打つにはKANAロックがON/OFFのどちらである必要があるか」
/// だけを持つ。
class _Step {
  const _Step(this.chord, {required this.needsKana, required this.isLetter});

  final KeyChord chord;
  final bool needsKana;

  /// ASCII英字（a-z/A-Z）かどうか。
  ///
  /// `KEYBOARD::scan2fmkeycode`（keyboard.cpp）はStandardモード
  /// （kana/ctrl/graph無し）のときだけ、`retval`が'A'-'Z'/'a'-'z'なら
  /// CAPSロック実点灯状態で大小を反転させる。かな文字はこの分岐を通らない
  /// （kana_pressedが真だとStandard分岐自体に入らない）ため、
  /// この反転はASCII英字ステップにだけ効く。
  final bool isLetter;
}

bool _isAsciiLetter(String ch) {
  final code = ch.codeUnitAt(0);
  return (code >= 0x41 && code <= 0x5a) || (code >= 0x61 && code <= 0x7a);
}

List<_Step> _buildSteps(String text, {required bool romajiToKana}) {
  final converted = romajiToKana
      ? convertRomajiToKana(text)
      : normalizeKanaText(text);
  final steps = <_Step>[];
  for (final rune in converted.runes) {
    final ch = String.fromCharCode(rune);
    if (ch == '\r') {
      continue; // "\r\n"のCRは無視し、"\n"だけをEnterとして扱う。
    }
    final asciiChord = chordForAscii(ch);
    if (asciiChord != null) {
      steps.add(
        _Step(asciiChord, needsKana: false, isLetter: _isAsciiLetter(ch)),
      );
      continue;
    }
    final kanaChord = chordForKana(ch);
    if (kanaChord != null) {
      steps.add(_Step(kanaChord, needsKana: true, isLetter: false));
      continue;
    }
    // どちらの表にもない文字（漢字等）は打てないため無視する。
  }
  return steps;
}

/// クリップボード文字列の自動キー入力エンジン（INP-03）。
///
/// design.md 8「自動キー入力は専用キューを使い、通常入力と競合する場合の
/// 優先順位をControllerで管理する」に基づき、キューと送出タイマーはこの
/// クラスだけが持つ。ネイティブ側には既存の`keyDown`/`keyUp`
/// （`BFM_CMD_KEY_DOWN`/`KEY_UP`）以外何も送らない。
///
/// タイミングは`native/core/upstream/src/vm/fm7/fm7.h`の
/// `USE_AUTO_KEY 5` / `USE_AUTO_KEY_RELEASE 6`
/// （win32版OSD専用、60fps換算で押下5フレーム・解放6フレーム）を踏襲する。
class AutoKeyEngine {
  static const _pressDuration = Duration(milliseconds: 83);
  static const _releaseDuration = Duration(milliseconds: 100);

  Timer? _timer;
  Completer<void>? _completer;
  bool _cancelled = false;

  bool get isRunning => _completer != null;

  /// [text]を1文字ずつ打鍵する。既に実行中なら何もしない。
  ///
  /// [initialKanaLock]は開始時点のKANAロック状態（LED、`LedState.kana`）。
  /// かな文字を打つために一時的にトグルした場合、終了時にこの状態へ戻す。
  ///
  /// [initialCapsLock]は開始時点のCAPSロック状態（LED、`LedState.caps`）。
  /// KANAと異なりCAPSはコア側をトグルしない（CAPSはASCII英字ステップの間
  /// だけ影響する持続状態のため、逐次トグルするとレースの余地が増える）。
  /// 代わりに、ASCII英字ステップだけ実際に送るShiftをCAPS状態とXORして
  /// 打ち消す（`scan2fmkeycode`のCAPS大小反転を相殺する）。
  Future<void> run(
    EmulatorSession session,
    String text, {
    required bool romajiToKana,
    required bool initialKanaLock,
    required bool initialCapsLock,
  }) async {
    if (isRunning) {
      return;
    }
    final steps = _buildSteps(text, romajiToKana: romajiToKana);
    if (steps.isEmpty) {
      return;
    }
    _cancelled = false;
    final completer = Completer<void>();
    _completer = completer;

    var currentKanaOn = initialKanaLock;
    var index = 0;
    var awaitingRelease = false;
    KeyChord? pending;
    // 送出中のステップが実際にShiftを伴うか。keyUpは必ず本体キーの直後
    // （下のawaitingRelease分岐、またはcancel分岐）で送る。keyDown直後に
    // 送ってしまうと、本体キーがまだ押されたままの間にコアの
    // `shift_pressed`がfalseへ戻り、その間に発生しうる別経路の
    // `scan2fmkeycode`再評価（オートリピート、Auto 5/8キーの後始末等、
    // `keyboard.cpp`）が非Shift側の文字を拾ってしまう恐れがある。
    var pendingShift = false;

    Future<void> finish() async {
      _timer?.cancel();
      _timer = null;
      if (currentKanaOn != initialKanaLock) {
        await session.keyDown(Win32Vk.kana);
        await session.keyUp(Win32Vk.kana);
      }
      _completer = null;
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    Future<void> step(Timer _) async {
      if (_cancelled) {
        if (pending != null) {
          await session.keyUp(pending!.vk);
          if (pendingShift) {
            await session.keyUp(Win32Vk.lshift);
          }
          pending = null;
          pendingShift = false;
        }
        await finish();
        return;
      }
      if (awaitingRelease) {
        await session.keyUp(pending!.vk);
        if (pendingShift) {
          await session.keyUp(Win32Vk.lshift);
        }
        pending = null;
        pendingShift = false;
        awaitingRelease = false;
        _timer?.cancel();
        _timer = Timer(_releaseDuration, () => step(_timer!));
        return;
      }
      if (index >= steps.length) {
        await finish();
        return;
      }
      final s = steps[index];
      index++;
      if (s.needsKana != currentKanaOn) {
        currentKanaOn = s.needsKana;
        await session.keyDown(Win32Vk.kana);
        await session.keyUp(Win32Vk.kana);
      }
      final effectiveShift = s.isLetter
          ? (s.chord.shift != initialCapsLock)
          : s.chord.shift;
      if (effectiveShift) {
        await session.keyDown(Win32Vk.lshift);
      }
      await session.keyDown(s.chord.vk);
      pending = s.chord;
      pendingShift = effectiveShift;
      awaitingRelease = true;
      _timer?.cancel();
      _timer = Timer(_pressDuration, () => step(_timer!));
    }

    _timer = Timer(Duration.zero, () => step(_timer!));
    return completer.future;
  }

  /// 実行中なら即座に停止する。保留中のキーがあればupを送り、KANAロックを
  /// 開始時の状態へ戻す。実行中でなければ何もしない。
  ///
  /// メニューの`Stop Paste`など、セッションがまだ生きている経路で使う。
  Future<void> cancel() async {
    if (!isRunning) {
      return;
    }
    _cancelled = true;
    final future = _completer!.future;
    await future;
  }

  /// `Timer`を同期的に取り消して即座に停止する。保留中のキーのupや
  /// KANAロックの復元は行わない（セッションがすでに手放されている
  /// 可能性がある経路で使うため、そこへは触れない）。
  ///
  /// `EmulatorController._teardown()`専用。`ref.onDispose`はそこを
  /// 待たないため、残った`Timer`はdispose後に発火してしまう
  /// （Flutter testの「pending timer」検出に引っかかる）。他の`Timer`
  /// 取消し（`_statsTimer`）と同じく、必ず同期的に真っ先に行う。
  void disposeNow() {
    _timer?.cancel();
    _timer = null;
    _cancelled = true;
    final completer = _completer;
    _completer = null;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
  }
}
