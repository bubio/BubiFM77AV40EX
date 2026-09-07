// packages/bubi_fm77av40ex_core の FFI 束縛が、実際にビルドした
// ネイティブライブラリへ届くことを確かめる。
//
// 確かめるのは次の点である。
//   - 公開シンボルがすべて解決できること（可視性とstripの検証）
//   - 不透明ハンドルを Dart 側で保持して往復できること
//   - エラーコードが Dart まで正しく伝わること
//   - FfiEmulatorSession が実ライブラリに対して正しく動くこと
//     （イベントの引き取り、状態の反映、リセットの完了通知、破棄の冪等性）
//
// アプリのビルドでは静的リンクした本体からシンボルを引くため、
// ここでは BUBI_CORE_LIBRARY で共有ライブラリを指定して読み込む。
// 実行は scripts/run_native_checks.sh から行う。
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:bubi_fm77av40ex/emulator/emulator_error.dart';
import 'package:bubi_fm77av40ex/emulator/emulator_event.dart';
import 'package:bubi_fm77av40ex/emulator/session_state.dart';
import 'package:bubi_fm77av40ex/platform/core_ffi/audio_sink.dart';
import 'package:bubi_fm77av40ex/platform/core_ffi/ffi_emulator_session.dart';
import 'package:bubi_fm77av40ex_core/bubi_fm77av40ex_core.dart';
import 'package:ffi/ffi.dart';

/// `AudioSink`は`package:flutter`に依存しないため、この検証でも
/// 実装を差し込める（`lib/platform/core_ffi/audio_sink.dart`）。
class _RecordingAudioSink implements AudioSink {
  int? startedSampleRate;
  int? startedChannels;
  int pushCount = 0;
  bool stopped = false;

  @override
  Future<void> start({required int sampleRate, required int channels}) async {
    startedSampleRate = sampleRate;
    startedChannels = channels;
  }

  @override
  void pushPcm16(Uint8List interleavedLittleEndianPcmBytes) {
    pushCount++;
  }

  double? lastVolume;

  @override
  void setVolume(double volume) {
    lastVolume = volume;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }
}

int failures = 0;

void check(bool condition, String what) {
  stdout.writeln('  [${condition ? ' ok ' : 'FAIL'}] $what');
  if (!condition) {
    failures++;
  }
}

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(
      'usage: dart tool/native_ffi_check.dart <library> <home-dir>',
    );
    exit(2);
  }
  final libraryPath = args[0];
  final homeDir = args[1];

  stdout.writeln('== シンボル解決');
  final library = DynamicLibrary.open(libraryPath);
  final bindings = BubiCoreBindings(library);
  check(true, '公開シンボルをすべて解決できる');

  stdout.writeln('== 引数検証の伝播');
  final options = calloc<BfmCreateOptions>();
  final out = calloc<Pointer<BfmSession>>();
  final empty = ''.toNativeUtf8();
  try {
    options.ref.homeDir = empty.cast<Char>();
    check(
      bindings.create(options, out) == BfmResult.invalidArgument,
      'home_dir が空なら invalidArgument が Dart まで伝わる',
    );
  } finally {
    calloc.free(empty);
  }

  stdout.writeln('== 生成・起動・停止・破棄の反復');
  final home = homeDir.toNativeUtf8();
  var cyclesOk = true;
  var everyCycleAdvanced = true;
  try {
    options.ref.homeDir = home.cast<Char>();
    for (var i = 0; i < 5; i++) {
      if (bindings.create(options, out) != BfmResult.ok) {
        cyclesOk = false;
        break;
      }
      final session = out.value;
      if (bindings.start(session) != BfmResult.ok) {
        cyclesOk = false;
        bindings.destroy(session);
        break;
      }

      // running まで待つ。
      var running = false;
      for (var waited = 0; waited < 5000; waited++) {
        if (bindings.getState(session) == BfmState.running) {
          running = true;
          break;
        }
        sleep(const Duration(milliseconds: 1));
      }
      if (!running) {
        cyclesOk = false;
        bindings.destroy(session);
        break;
      }

      final idOut = calloc<Uint64>();
      final stats = calloc<BfmStats>();
      try {
        if (bindings.reset(session, BfmResetKind.special, idOut) !=
                BfmResult.ok ||
            idOut.value == 0) {
          cyclesOk = false;
        }
        sleep(const Duration(milliseconds: 50));
        if (bindings.getStats(session, stats) != BfmResult.ok ||
            stats.ref.framesRun == 0) {
          everyCycleAdvanced = false;
        }
        if (stats.ref.vmAccessViolations != 0) {
          cyclesOk = false;
        }
      } finally {
        calloc.free(stats);
        calloc.free(idOut);
      }

      bindings.stop(session);
      bindings.destroy(session);
    }
  } finally {
    calloc.free(home);
    calloc.free(out);
    calloc.free(options);
  }

  check(cyclesOk, '5回の生成・起動・リセット・停止・破棄が成功する');
  check(everyCycleAdvanced, 'すべての回で Core thread がフレームを進める');

  await _checkEmulatorSession(bindings, homeDir);

  stdout.writeln('');
  stdout.writeln(failures == 0 ? 'すべて合格' : '失敗あり');
  exit(failures == 0 ? 0 : 1);
}

/// `lib/platform/core_ffi/` の実装を実ライブラリに対して動かす。
///
/// 単体テストは dylib を読み込まないため、ここが唯一の実動確認になる。
Future<void> _checkEmulatorSession(
  BubiCoreBindings bindings,
  String homeDir,
) async {
  stdout.writeln('== FfiEmulatorSession');

  // ダミーROMを1つ置き、結線がDart側の引数からも効くことを見る。
  // 本物のROMは要らない。
  final romDir = Directory('$homeDir/dart-check-roms')
    ..createSync(recursive: true);
  File('${romDir.path}/INITIATE.ROM')
      .writeAsBytesSync(List<int>.filled(8192, 0));

  final audioSink = _RecordingAudioSink();
  final session = FfiEmulatorSession.create(
    homeDir: homeDir,
    romDir: romDir.path,
    bindings: bindings,
    audio: audioSink,
  );
  final received = <EmulatorEvent>[];
  final subscription = session.events.listen(received.add);

  check(session.state == SessionState.stopped, '生成直後は stopped');

  await session.start();
  var running = false;
  for (var waited = 0; waited < 500; waited++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (session.state == SessionState.running) {
      running = true;
      break;
    }
  }
  check(running, 'ネイティブのスナップショットから running を読む');

  // 状態のスナップショットは権威なので、周期的な引き取りより先に進む。
  // イベントの配布は別に待つ。
  var sawLifecycleEvent = false;
  for (var waited = 0; waited < 500; waited++) {
    sawLifecycleEvent = received.whereType<LifecycleChanged>().any(
      (event) => event.state == SessionState.running,
    );
    if (sawLifecycleEvent) {
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  check(sawLifecycleEvent, 'イベントを引き取って LifecycleChanged を配る');

  final coreDirectory = session.readCoreDirectory();
  check(coreDirectory.isNotEmpty, 'コアの読込みディレクトリを取得できる');
  check(
    Link('${coreDirectory}INITIATE.ROM').existsSync(),
    'romDir のROMへリンクが張られる',
  );

  final bootCommandId = await session.setBootMode(BootMode.dos);
  check(bootCommandId > 0, 'ブートモードの変更を投入できる');

  final speedCommandId = await session.setSpeedMultiplier(SpeedMultiplier.x4);
  check(speedCommandId > 0, 'CPU速度倍率の変更を投入できる（SYS-03）');

  final fullSpeedOnId = await session.setFullSpeed(true);
  check(fullSpeedOnId > 0, 'Full Speedを有効化できる（SYS-03の無制限）');
  final fullSpeedOffId = await session.setFullSpeed(false);
  check(fullSpeedOffId > 0, 'Full Speedを無効化できる');

  final cpuTypeCommandId = await session.setCpuType(CpuType.slow);
  check(cpuTypeCommandId > 0, 'CPU種別の変更を投入できる（SYS-05）');

  final optionSwitchCommandId = await session.setRunOptionSwitches(
    const RunOptionSwitches(cycleSteal: true, syncToHsync: true),
  );
  check(optionSwitchCommandId > 0, 'オプションスイッチの変更を投入できる（SYS-06）');

  final soundVolumeCommandId = await session.setSoundChannelVolume(
    SoundChannel.beep,
    0.5,
  );
  check(soundVolumeCommandId > 0, '標準音声チャンネルの音量変更を投入できる（AUD-03）');

  final writeProtectId = await session.setFddWriteProtect(0, true);
  check(writeProtectId > 0, 'FDDの書込み保護を投入できる（FDD-06）');
  final timingId = await session.setFddTiming(0, true);
  check(timingId > 0, 'FDDのタイミング補正を投入できる（FDD-06）');
  final crcId = await session.setFddCrcCheck(0, true);
  check(crcId > 0, 'FDDのCRCエラー無視を投入できる（FDD-06）');

  final blankPath = '$homeDir/dart-check-blank.d88';
  final createBlankId = await session.createBlankFdd(
    FddMediaType.d2,
    blankPath,
  );
  check(createBlankId > 0, '空の2Dディスク作成を投入できる（FDD-05）');
  for (
    var waited = 0;
    waited < 500 && !File(blankPath).existsSync();
    waited++
  ) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  check(File(blankPath).existsSync(), '作成した空ディスクのファイルが実在する');

  final bankInfo = session.getFddBankInfo(0);
  check(bankInfo.bankNum == 0, '未挿入ドライブのbank_numは0（FDD-04）');

  check(session.getFddWriteProtect(0) == false, '未挿入ドライブの書込み保護はfalse（FDD-06）');

  Future<CommandCompleted?> waitForCompletion(int commandId) async {
    for (var waited = 0; waited < 500; waited++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final completion = received.whereType<CommandCompleted>().where((event) {
        return event.commandId == commandId;
      }).firstOrNull;
      if (completion != null) {
        return completion;
      }
    }
    return null;
  }

  final statePath = '$homeDir/dart-check-state.bin';
  final saveStateId = await session.saveState(statePath);
  check(saveStateId > 0, '状態保存を投入できる（STA-01）');
  final saveCompletion = await waitForCompletion(saveStateId);
  check(saveCompletion != null, '状態保存の完了通知が届く');
  check(saveCompletion?.succeeded ?? false, '状態保存は成功で完了する');
  check(File(statePath).existsSync(), '保存先に実ファイルが残る');

  final loadStateId = await session.loadState(statePath);
  check(loadStateId > 0, '状態読込みを投入できる（STA-02）');
  final loadCompletion = await waitForCompletion(loadStateId);
  check(loadCompletion != null, '状態読込みの完了通知が届く');
  check(loadCompletion?.succeeded ?? false, '状態読込みは成功で完了する');

  final corruptStatePath = '$homeDir/dart-check-state-corrupt.bin';
  final corruptBytes = Uint8List.fromList(File(statePath).readAsBytesSync());
  corruptBytes[0] = corruptBytes[0] ^ 0xFF;
  File(corruptStatePath).writeAsBytesSync(corruptBytes);
  final loadCorruptId = await session.loadState(corruptStatePath);
  final loadCorruptCompletion = await waitForCompletion(loadCorruptId);
  check(loadCorruptCompletion != null, '壊れた状態読込みの完了通知が届く');
  check(
    loadCorruptCompletion?.error == EmulatorErrorCode.stateIncompatible,
    '壊れた状態読込みはstateIncompatibleで拒否される（STA-02）',
  );

  final commandId = await session.reset(ResetKind.special);
  check(commandId > 0, '特殊リセットの連番IDが返る');

  final completion = await waitForCompletion(commandId);
  check(completion != null, '同じIDの完了通知が Dart まで届く');
  check(completion?.succeeded ?? false, 'リセットは成功で完了する');

  // 音声はメインisolateのTimerで周期的に引き出すため、届くまで少し待つ
  // （lib/platform/core_ffi/ffi_emulator_session.dart の _audioPullInterval）。
  for (var waited = 0; waited < 100 && audioSink.pushCount == 0; waited++) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  check(
    audioSink.startedSampleRate == 48000,
    '音声フォーマットは48kHzで開始する（design.md 7）',
  );
  check(audioSink.startedChannels == 2, '音声フォーマットはステレオで開始する');
  check(audioSink.pushCount > 0, 'AudioSinkへPCMが供給される');

  final stats = session.readStats();
  check(stats.framesRun > 0, 'Core thread がフレームを進めている');
  check(stats.vmAccessViolations == 0, 'VM操作はCore threadに閉じている');

  await session.stop();
  check(session.state == SessionState.stopped, '停止後は stopped');
  check(audioSink.stopped, '停止時にAudioSinkも止める');

  await subscription.cancel();
  await session.dispose();
  await session.dispose();
  check(true, '破棄は冪等');

  var rejectedAfterDispose = false;
  try {
    await session.reset(ResetKind.normal);
  } on EmulatorException catch (error) {
    rejectedAfterDispose = error.code == EmulatorErrorCode.invalidState;
  }
  check(rejectedAfterDispose, '破棄後の操作は invalidState で拒否する');
}
