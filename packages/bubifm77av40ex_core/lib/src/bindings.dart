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
          .asFunction(),
      getCoreDirectory = library
          .lookup<
            NativeFunction<
              Int32 Function(Pointer<BfmSession>, Pointer<Char>, Uint32)
            >
          >('bfm_get_core_directory')
          .asFunction(),
      acquireVideoFrame = library
          .lookup<
            NativeFunction<
              Int32 Function(Pointer<BfmSession>, Pointer<BfmVideoFrame>)
            >
          >('bfm_acquire_video_frame')
          .asFunction(),
      releaseVideoFrame = library
          .lookup<NativeFunction<Void Function(Pointer<BfmSession>, Uint64)>>(
            'bfm_release_video_frame',
          )
          .asFunction(),
      videoGeneration = library
          .lookup<NativeFunction<Uint64 Function(Pointer<BfmSession>)>>(
            'bfm_video_generation',
          )
          .asFunction(),
      readAudio = library
          .lookup<
            NativeFunction<
              Int32 Function(Pointer<BfmSession>, Pointer<Int16>, Uint32)
            >
          >('bfm_read_audio')
          .asFunction(),
      readAudioAvailable = library
          .lookup<
            NativeFunction<
              Int32 Function(
                Pointer<BfmSession>,
                Pointer<Int16>,
                Uint32,
                Pointer<Uint32>,
              )
            >
          >('bfm_read_audio_available')
          .asFunction(),
      getAudioFormat = library
          .lookup<
            NativeFunction<
              Int32 Function(
                Pointer<BfmSession>,
                Pointer<Uint32>,
                Pointer<Uint32>,
              )
            >
          >('bfm_get_audio_format')
          .asFunction(),
      getMediaAccess = library
          .lookup<
            NativeFunction<Int32 Function(Pointer<BfmSession>, Pointer<Uint32>)>
          >('bfm_get_media_access')
          .asFunction(),
      getFddBankInfo = library
          .lookup<
            NativeFunction<
              Int32 Function(
                Pointer<BfmSession>,
                Int32,
                Pointer<Int32>,
                Pointer<Int32>,
              )
            >
          >('bfm_get_fdd_bank_info')
          .asFunction(),
      getFddWriteProtect = library
          .lookup<
            NativeFunction<
              Int32 Function(Pointer<BfmSession>, Int32, Pointer<Int32>)
            >
          >('bfm_get_fdd_write_protect')
          .asFunction(),
      getCmtStatus = library
          .lookup<
            NativeFunction<
              Int32 Function(Pointer<BfmSession>, Pointer<BfmCmtStatus>)
            >
          >('bfm_get_cmt_status')
          .asFunction(),
      setJoystickState = library
          .lookup<
            NativeFunction<Int32 Function(Pointer<BfmSession>, Int32, Uint32)>
          >('bfm_set_joystick_state')
          .asFunction(),
      setPaused = library
          .lookup<NativeFunction<Int32 Function(Pointer<BfmSession>, Int32)>>(
            'bfm_set_paused',
          )
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
  final int Function(Pointer<BfmSession>, Pointer<Char>, int) getCoreDirectory;
  final int Function(Pointer<BfmSession>, Pointer<BfmVideoFrame>)
  acquireVideoFrame;
  final void Function(Pointer<BfmSession>, int) releaseVideoFrame;
  final int Function(Pointer<BfmSession>) videoGeneration;
  final int Function(Pointer<BfmSession>, Pointer<Int16>, int) readAudio;

  /// 溜まっている分だけ読み、読んだフレーム数を返す（bfm_read_audio_available）。
  /// 無音で埋めない。
  final int Function(Pointer<BfmSession>, Pointer<Int16>, int, Pointer<Uint32>)
  readAudioAvailable;
  final int Function(Pointer<BfmSession>, Pointer<Uint32>, Pointer<Uint32>)
  getAudioFormat;

  /// FD1/FD2アクセス状態のread-and-clearポーリング（bfm_get_media_access）。
  /// 消費者は1つに保つこと。
  final int Function(Pointer<BfmSession>, Pointer<Uint32>) getMediaAccess;

  /// D88のバンク情報（bfm_get_fdd_bank_info、M3 FDD-04）。
  final int Function(Pointer<BfmSession>, int, Pointer<Int32>, Pointer<Int32>)
  getFddBankInfo;

  /// ドライブごとの書込み保護の実際値（bfm_get_fdd_write_protect、M3 FDD-06）。
  final int Function(Pointer<BfmSession>, int, Pointer<Int32>)
  getFddWriteProtect;

  /// CMTの現在状態（bfm_get_cmt_status、M4 CMT-05）。
  final int Function(Pointer<BfmSession>, Pointer<BfmCmtStatus>) getCmtStatus;

  /// ジョイスティックの直接入力（bfm_set_joystick_state、M3 INP-04）。
  final int Function(Pointer<BfmSession>, int, int) setJoystickState;

  /// 一時停止（bfm_set_paused）。
  final int Function(Pointer<BfmSession>, int) setPaused;
}

/// Windowsでコアを含むプラグインDLLのファイル名。
const String bubiCoreWindowsLibraryName = 'bubifm77av40ex_core_plugin.dll';

/// Linuxでコアを含むプラグイン共有ライブラリのファイル名。
const String bubiCoreLinuxLibraryName = 'libbubifm77av40ex_core_plugin.so';

/// ネイティブライブラリを開く。
///
/// macOS ではプラグインの静的ライブラリがアプリ本体へ `-force_load` されるため、
/// 別ファイルではなくプロセス自身からシンボルを引く。
/// Windows ではコアをプラグインのDLLへ取り込んでいるため、そのDLLを開く
/// （packages/bubifm77av40ex_core/windows/CMakeLists.txt）。映像テクスチャも
/// 同じDLLにあり、プロセス内のコアは1つになる。DLLは実行ファイルと同じ
/// ディレクトリに置かれ、既にランナーが読み込み済みのため同じ実体が返る。
/// Linux も同じ構成で、バンドルの `lib/` にある共有ライブラリを開く
/// （packages/bubifm77av40ex_core/linux/CMakeLists.txt）。ランナーが
/// 読み込み済みのため、動的リンカーは同じsonameの実体を返す。
/// Android/iOS は担当マイルストーン（M7）で足す。
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
  if (Platform.isWindows) {
    return DynamicLibrary.open(bubiCoreWindowsLibraryName);
  }
  if (Platform.isLinux) {
    return DynamicLibrary.open(bubiCoreLinuxLibraryName);
  }
  throw UnsupportedError('${Platform.operatingSystem} 向けのネイティブコアはまだ組み込んでいません。');
}
