import 'package:bubi_fm77av40ex/emulator/emulator_error.dart';
import 'package:bubi_fm77av40ex/emulator/emulator_event.dart';
import 'package:bubi_fm77av40ex/emulator/session_state.dart';
import 'package:bubi_fm77av40ex/platform/core_ffi/native_conversions.dart';
import 'package:bubi_fm77av40ex_core/bubi_fm77av40ex_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// C ABI の値と `lib/emulator/` の型の対応を検査する。
///
/// ネイティブライブラリを読み込まないため、CIの通常のunit testで実行できる。
/// ライブラリを実際に呼ぶ検証は native/host/session_test.cpp と
/// scripts/run_native_checks.sh が行う。
void main() {
  group('SYS-01 bfm_result の変換', () {
    test('既知の値をすべて対応付ける', () {
      expect(
        errorCodeFromNative(BfmResult.invalidArgument),
        EmulatorErrorCode.invalidArgument,
      );
      expect(
        errorCodeFromNative(BfmResult.invalidState),
        EmulatorErrorCode.invalidState,
      );
      expect(
        errorCodeFromNative(BfmResult.queueFull),
        EmulatorErrorCode.queueFull,
      );
      expect(errorCodeFromNative(BfmResult.noEvent), EmulatorErrorCode.noEvent);
      expect(
        errorCodeFromNative(BfmResult.coreFailed),
        EmulatorErrorCode.coreFailed,
      );
      expect(
        errorCodeFromNative(BfmResult.unsupported),
        EmulatorErrorCode.unsupported,
      );
      expect(
        errorCodeFromNative(BfmResult.internal),
        EmulatorErrorCode.internal,
      );
    });

    test('未知の値は unknown にし、別のエラーへ吸収させない', () {
      expect(errorCodeFromNative(9999), EmulatorErrorCode.unknown);
      expect(errorCodeFromNative(-1), EmulatorErrorCode.unknown);
    });

    test('すべてのエラーコードに説明がある', () {
      for (final code in EmulatorErrorCode.values) {
        expect(describeErrorCode(code), isNotEmpty, reason: code.name);
      }
    });
  });

  group('SYS-01 bfm_state の変換', () {
    test('既知の値をすべて対応付ける', () {
      expect(sessionStateFromNative(BfmState.stopped), SessionState.stopped);
      expect(sessionStateFromNative(BfmState.starting), SessionState.starting);
      expect(sessionStateFromNative(BfmState.running), SessionState.running);
      expect(sessionStateFromNative(BfmState.stopping), SessionState.stopping);
      expect(sessionStateFromNative(BfmState.failed), SessionState.failed);
    });

    test('未知の値は failed にし、動作中と誤認させない', () {
      expect(sessionStateFromNative(42), SessionState.failed);
    });
  });

  group('SYS-02 リセット種別の変換', () {
    test('通常と特殊を区別する', () {
      expect(resetKindToNative(ResetKind.normal), BfmResetKind.normal);
      expect(resetKindToNative(ResetKind.special), BfmResetKind.special);
      expect(
        resetKindToNative(ResetKind.normal),
        isNot(resetKindToNative(ResetKind.special)),
      );
    });
  });

  group('NFR-03 イベントの変換', () {
    test('lifecycleChanged は arg0 を状態として読む', () {
      final event = emulatorEventFromNative(
        kind: BfmEventKind.lifecycleChanged,
        code: 0,
        commandId: 0,
        arg0: BfmState.running,
      );
      expect(event, isA<LifecycleChanged>());
      expect((event as LifecycleChanged).state, SessionState.running);
    });

    test('commandCompleted は成功時にエラーを持たない', () {
      final event = emulatorEventFromNative(
        kind: BfmEventKind.commandCompleted,
        code: BfmResult.ok,
        commandId: 7,
        arg0: 0,
      );
      expect(event, isA<CommandCompleted>());
      final completed = event as CommandCompleted;
      expect(completed.commandId, 7);
      expect(completed.error, isNull);
      expect(completed.succeeded, isTrue);
    });

    test('未実装コマンドの完了は unsupported を持つ', () {
      final event = emulatorEventFromNative(
        kind: BfmEventKind.commandCompleted,
        code: BfmResult.unsupported,
        commandId: 12,
        arg0: 0,
      ) as CommandCompleted;
      expect(event.error, EmulatorErrorCode.unsupported);
      expect(event.succeeded, isFalse);
    });

    test('error は code をエラー分類として読む', () {
      final event = emulatorEventFromNative(
        kind: BfmEventKind.error,
        code: BfmResult.coreFailed,
        commandId: 0,
        arg0: 0,
      );
      expect(event, isA<EmulatorErrorOccurred>());
      expect(
        (event as EmulatorErrorOccurred).code,
        EmulatorErrorCode.coreFailed,
      );
    });

    test('未実装の種別は捨てずに UnhandledEmulatorEvent にする', () {
      final event = emulatorEventFromNative(
        kind: BfmEventKind.fddMechanical,
        code: 0,
        commandId: 0,
        arg0: 0,
      );
      expect(event, isA<UnhandledEmulatorEvent>());
      expect(
        (event as UnhandledEmulatorEvent).nativeKind,
        BfmEventKind.fddMechanical,
      );
    });
  });

  group('SYS-01 コマンド種別の型空間', () {
    test('design.md 4.2 の分類が上位バイトで分かれている', () {
      const byCategory = <int, List<int>>{
        0x01: [BfmCommandKind.reset, BfmCommandKind.specialReset],
        0x02: [
          BfmCommandKind.setSpeedMultiplier,
          BfmCommandKind.setFullSpeed,
          BfmCommandKind.setBootMode,
          BfmCommandKind.setCpuType,
        ],
        0x03: [
          BfmCommandKind.insertFdd,
          BfmCommandKind.ejectFdd,
          BfmCommandKind.setFddWriteProtect,
          BfmCommandKind.setFddTiming,
          BfmCommandKind.setFddCrcCheck,
          BfmCommandKind.insertCmt,
          BfmCommandKind.ejectCmt,
          BfmCommandKind.controlCmt,
        ],
        0x04: [
          BfmCommandKind.keyDown,
          BfmCommandKind.keyUp,
          BfmCommandKind.mouse,
          BfmCommandKind.joystick,
          BfmCommandKind.autoKey,
        ],
        0x05: [
          BfmCommandKind.setSoundType,
          BfmCommandKind.setOptionSwitch,
          BfmCommandKind.setVolume,
          BfmCommandKind.setFrameRate,
        ],
        0x06: [BfmCommandKind.saveState, BfmCommandKind.loadState],
        0x07: [
          BfmCommandKind.debuggerOpen,
          BfmCommandKind.debuggerClose,
          BfmCommandKind.debuggerExecute,
        ],
      };

      final seen = <int>{};
      for (final entry in byCategory.entries) {
        for (final kind in entry.value) {
          expect(kind >> 8, entry.key, reason: '0x${kind.toRadixString(16)}');
          expect(
            seen.add(kind),
            isTrue,
            reason: '重複: 0x${kind.toRadixString(16)}',
          );
        }
      }
    });
  });
}
