import 'dart:ffi';
import 'dart:io';

import 'native_types.dart';

/// native/bridge/include/bubi_fm77av.h の関数への束縛。
///
/// ここは C ABI をそのまま Dart から呼べるようにするだけの層で、
/// 状態や方針は持たない。エラーコードの解釈やライフサイクルの管理は
/// アプリ側の `lib/platform/core_ffi/` が行う。
final class BubiCoreBindings {
  BubiCoreBindings(DynamicLibrary library)
    : create = library
          .lookup<
            NativeFunction<
              Int32 Function(
                Pointer<BfmCreateOptions>,
                Pointer<Pointer<BfmSession>>,
              )
            >
          >('bfm_create')
          .asFunction(),
      destroy = library
          .lookup<NativeFunction<Void Function(Pointer<BfmSession>)>>(
            'bfm_destroy',
          )
          .asFunction(),
      start = library
          .lookup<NativeFunction<Int32 Function(Pointer<BfmSession>)>>(
            'bfm_start',
          )
          .asFunction(),
      stop = library
          .lookup<NativeFunction<Int32 Function(Pointer<BfmSession>)>>(
            'bfm_stop',
          )
          .asFunction(),
      reset = library
          .lookup<
            NativeFunction<
              Int32 Function(Pointer<BfmSession>, Int32, Pointer<Uint64>)
            >
          >('bfm_reset')
          .asFunction(),
      sendCommand = library
          .lookup<
            NativeFunction<
              Int32 Function(
                Pointer<BfmSession>,
                Pointer<BfmCommand>,
                Pointer<Uint64>,
              )
            >
          >('bfm_send_command')
          .asFunction(),
      pollEvent = library
          .lookup<
            NativeFunction<
              Int32 Function(Pointer<BfmSession>, Pointer<BfmEvent>)
            >
          >('bfm_poll_event')
          .asFunction(),
      getState = library
          .lookup<NativeFunction<Int32 Function(Pointer<BfmSession>)>>(
            'bfm_get_state',
          )
          .asFunction(),
      getStats = library
          .lookup<
            NativeFunction<
              Int32 Function(Pointer<BfmSession>, Pointer<BfmStats>)
            >
          >('bfm_get_stats')
          .asFunction();

  /// 既定のライブラリを開いて束縛する。
  factory BubiCoreBindings.open() => BubiCoreBindings(openBubiCoreLibrary());

  final int Function(Pointer<BfmCreateOptions>, Pointer<Pointer<BfmSession>>)
  create;
  final void Function(Pointer<BfmSession>) destroy;
  final int Function(Pointer<BfmSession>) start;
  final int Function(Pointer<BfmSession>) stop;
  final int Function(Pointer<BfmSession>, int, Pointer<Uint64>) reset;
  final int Function(Pointer<BfmSession>, Pointer<BfmCommand>, Pointer<Uint64>)
  sendCommand;
  final int Function(Pointer<BfmSession>, Pointer<BfmEvent>) pollEvent;
  final int Function(Pointer<BfmSession>) getState;
  final int Function(Pointer<BfmSession>, Pointer<BfmStats>) getStats;
}

/// ネイティブライブラリを開く。
///
/// macOS ではプラグインの静的ライブラリがアプリ本体へ `-force_load` されるため、
/// 別ファイルではなくプロセス自身からシンボルを引く。
/// Linux/Windows/Android/iOS は担当マイルストーン（M4〜M6）で足す。
///
/// `BUBI_CORE_LIBRARY` が指す共有ライブラリがあればそれを優先する。
/// Flutter を通さない Dart のテストや検査スクリプトから使う。
DynamicLibrary openBubiCoreLibrary() {
  final override = Platform.environment['BUBI_CORE_LIBRARY'];
  if (override != null && override.isNotEmpty) {
    return DynamicLibrary.open(override);
  }
  if (Platform.isMacOS) {
    return DynamicLibrary.process();
  }
  throw UnsupportedError('${Platform.operatingSystem} 向けのネイティブコアはまだ組み込んでいません。');
}
