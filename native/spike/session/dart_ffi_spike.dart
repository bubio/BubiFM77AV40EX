// 技術検証spike（development_plan.md 5.3「C ABI」）のDart側。
//
// 同じC ABIをDart FFIから呼び、次だけを確かめる。
//   - 共有ライブラリのシンボルがDartから解決できる
//   - 不透明ハンドルをDart側で保持できる（Pointer<Void>相当）
//   - 生成・起動・停止・破棄を繰り返しても異常終了しない
//   - エラーコードがそのままDartへ伝わる
//
// これは製品コードではない。M1 WP1で lib/platform/core_ffi/ として作り直す。
//
// 実行: fvm dart run native/spike/session/dart_ffi_spike.dart <dylib> <home>
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart' as pkg_ffi;

// --- C ABI の型定義（bfm_session_spike.h と一致させる） ---

const int bfmOk = 0;
const int bfmErrInvalidArgument = 1;
const int bfmErrInvalidState = 2;

const int bfmStateStopped = 0;
const int bfmStateRunning = 2;

final class BfmCreateOptions extends Struct {
  external Pointer<Utf8Bytes> homeDir;
  @Uint32()
  external int commandQueueCapacity;
  @Uint32()
  external int eventQueueCapacity;
}

// package:ffi を使わずに済ませるための最小のUTF-8ポインタ型。
final class Utf8Bytes extends Opaque {}

typedef _CreateNative = Int32 Function(
  Pointer<BfmCreateOptions>,
  Pointer<Pointer<Void>>,
);
typedef _CreateDart = int Function(
  Pointer<BfmCreateOptions>,
  Pointer<Pointer<Void>>,
);

typedef _HandleNative = Int32 Function(Pointer<Void>);
typedef _HandleDart = int Function(Pointer<Void>);

typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _DestroyDart = void Function(Pointer<Void>);

int failures = 0;

void check(bool condition, String what) {
  stdout.writeln('  [${condition ? ' ok ' : 'FAIL'}] $what');
  if (!condition) failures++;
}

void main(List<String> args) {
  if (args.length < 2) {
    stderr.writeln('usage: dart_ffi_spike.dart <dylib path> <home dir>');
    exit(2);
  }
  final libraryPath = args[0];
  final homeDir = args[1];

  stdout.writeln('C ABI: the same boundary called from Dart FFI');

  final library = DynamicLibrary.open(libraryPath);
  check(true, 'the shared library loads');

  final create = library.lookupFunction<_CreateNative, _CreateDart>(
    'bfm_create',
  );
  final start = library.lookupFunction<_HandleNative, _HandleDart>('bfm_start');
  final stop = library.lookupFunction<_HandleNative, _HandleDart>('bfm_stop');
  final getState = library.lookupFunction<_HandleNative, _HandleDart>(
    'bfm_get_state',
  );
  final destroy = library.lookupFunction<_DestroyNative, _DestroyDart>(
    'bfm_destroy',
  );
  check(true, 'every symbol of the C ABI resolves');

  // 引数検証がDartへそのまま返る。
  final nullOut = pkg_ffi.calloc<Pointer<Void>>();
  check(
    create(Pointer.fromAddress(0), nullOut) == bfmErrInvalidArgument,
    'bfm_create rejects null options with the same error code',
  );
  pkg_ffi.calloc.free(nullOut);

  // 生成・起動・停止・破棄を繰り返す。
  const cycles = 5;
  var allOk = true;
  for (var i = 0; i < cycles; i++) {
    final home = homeDir.toNativeUtf8Bytes();
    final options = pkg_ffi.calloc<BfmCreateOptions>();
    options.ref.homeDir = home;
    options.ref.commandQueueCapacity = 0;
    options.ref.eventQueueCapacity = 0;

    final out = pkg_ffi.calloc<Pointer<Void>>();
    if (create(options, out) != bfmOk) {
      allOk = false;
    } else {
      final session = out.value;
      if (start(session) != bfmOk) allOk = false;

      // 起動完了を待つ。Core threadはDartとは無関係に走る。
      var running = false;
      for (var w = 0; w < 3000 && !running; w++) {
        running = getState(session) == bfmStateRunning;
        if (!running) sleep(const Duration(milliseconds: 1));
      }
      if (!running) allOk = false;

      // 二重開始のエラーコードもDartへ伝わる。
      if (start(session) != bfmErrInvalidState) allOk = false;

      if (stop(session) != bfmOk) allOk = false;
      if (getState(session) != bfmStateStopped) allOk = false;
      destroy(session);
    }

    pkg_ffi.calloc.free(out);
    pkg_ffi.calloc.free(options);
    pkg_ffi.calloc.free(home.cast());
  }

  check(allOk, '$cycles cycles of create/start/stop/destroy succeed from Dart');

  if (failures != 0) {
    stdout.writeln('\ndart ffi spike FAILED ($failures checks)');
    exit(1);
  }
  stdout.writeln('\ndart ffi spike passed');
}

extension on String {
  /// NUL終端のUTF-8バイト列をネイティブヒープへ確保する。
  Pointer<Utf8Bytes> toNativeUtf8Bytes() {
    final bytes = codeUnits;
    final pointer = pkg_ffi.calloc<Uint8>(bytes.length + 1);
    for (var i = 0; i < bytes.length; i++) {
      pointer[i] = bytes[i];
    }
    pointer[bytes.length] = 0;
    return pointer.cast();
  }
}
