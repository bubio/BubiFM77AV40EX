import 'package:bubi_fm77av40ex/emulator/emulator_error.dart';
import 'package:bubi_fm77av40ex/emulator/emulator_event.dart';
import 'package:bubi_fm77av40ex/emulator/emulator_stats.dart';
import 'package:bubi_fm77av40ex/emulator/led_state.dart';
import 'package:bubi_fm77av40ex/emulator/session_state.dart';
import 'package:bubi_fm77av40ex/features/display/screen_filter.dart';
import 'package:bubi_fm77av40ex/features/session/emulator_controller.dart';
import 'package:bubi_fm77av40ex/features/session/emulator_state.dart';
import 'package:bubi_fm77av40ex/features/session/input/win32_vk.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// クリップボードの内容をテストから差し替える（INP-03）。`null`で未設定
/// （`Clipboard.getData`が`null`を返す）に戻す。
void _setClipboardText(String? text) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.getData') {
          return text == null ? null : {'text': text};
        }
        return null;
      });
}

/// FDD挿入・排出（design.md 16.1）の検査。原本は複製してからコアへ渡し、
/// 排出完了を待ってから作業領域を原本へ書き戻すことをFakeで確かめる。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeEmulatorSession session;
  late FakeExternalFileAccess externalFileAccess;
  late FakeCacheWorkspace cacheWorkspace;
  late FakeAppDataPaths appDataPaths;
  late ProviderContainer container;
  late NotifierProvider<EmulatorController, EmulatorViewState> provider;

  setUp(() async {
    _setClipboardText(null);
    session = FakeEmulatorSession();
    externalFileAccess = FakeExternalFileAccess();
    cacheWorkspace = FakeCacheWorkspace();
    appDataPaths = FakeAppDataPaths();
    provider = NotifierProvider<EmulatorController, EmulatorViewState>(
      () => EmulatorController(
        appDataPaths: appDataPaths,
        externalFileAccess: externalFileAccess,
        cacheWorkspace: cacheWorkspace,
        preferences: FakePreferencesStore(),
        createSession: ({
          required String homeDir,
          String? romDir,
          BootMode bootMode = BootMode.basic,
        }) => session,
      ),
    );
    container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(provider.notifier).launch();
  });

  EmulatorController controller() => container.read(provider.notifier);
  EmulatorViewState state() => container.read(provider);

  test('SYS-04 bootModeを渡したリセットはsetBootModeを先に呼び、状態も更新する', () async {
    await controller().reset(ResetKind.normal, bootMode: BootMode.dos);

    expect(session.setBootModeCalls, [BootMode.dos]);
    expect(session.resetCalls, [ResetKind.normal]);
    expect(state().bootMode, BootMode.dos);
  });

  test('VID-04 setScanlineEnabledは即座にstateへ反映される（コアへは送らない）', () {
    expect(state().scanlineEnabled, isFalse);
    controller().setScanlineEnabled(true);
    expect(state().scanlineEnabled, isTrue);
  });

  test('VID-04 setHostFilterは即座にstateへ反映される（コアへは送らない）', () {
    expect(state().hostFilter, HostScreenFilter.none);
    controller().setHostFilter(HostScreenFilter.rgb);
    expect(state().hostFilter, HostScreenFilter.rgb);
  });

  test('SYS-04 bootModeを渡さないリセットはsetBootModeを呼ばない', () async {
    await controller().reset(ResetKind.special);

    expect(session.setBootModeCalls, isEmpty);
    expect(session.resetCalls, [ResetKind.special]);
  });

  test('SYS-03 CPU速度倍率は起動中ならコアへ即時に送り、状態も更新する', () async {
    await controller().setSpeedMultiplier(SpeedMultiplier.x8);

    expect(session.setSpeedMultiplierCalls.last, SpeedMultiplier.x8);
    expect(state().speedMultiplier, SpeedMultiplier.x8);
  });

  test('SYS-03 Full Speedは起動中ならコアへ即時に送り、状態も更新する', () async {
    await controller().setFullSpeed(true);

    expect(session.setFullSpeedCalls.last, isTrue);
    expect(state().fullSpeed, isTrue);
  });

  test('SYS-05 CPU種別は起動中ならコアへ即時に送り、状態も更新する', () async {
    await controller().setCpuType(CpuType.slow);

    expect(session.setCpuTypeCalls.last, CpuType.slow);
    expect(state().cpuType, CpuType.slow);
  });

  test('SYS-06 オプションスイッチは起動中ならコアへ即時に送り、状態も更新する', () async {
    const switches = RunOptionSwitches(cycleSteal: true, extendedRam: true);
    await controller().setRunOptionSwitches(switches);

    expect(session.setRunOptionSwitchesCalls.last, switches);
    expect(state().optionSwitches, switches);
  });

  test('AUD-03 チャンネル音量は起動中ならコアへ即時に送り、状態も更新する', () async {
    await controller().setSoundChannelVolume(SoundChannel.beep, 0.5);

    expect(session.setSoundChannelVolumeCalls.last, (SoundChannel.beep, 0.5));
    expect(state().soundVolumes.beep, 0.5);
    // 他チャンネルは既定のまま。
    expect(state().soundVolumes.opnFm, 1.0);
  });

  test('実行設定は次回launch時に新しいセッションへ再適用される', () async {
    await controller().setSpeedMultiplier(SpeedMultiplier.x2);
    await controller().setFullSpeed(true);
    await controller().setCpuType(CpuType.slow);
    const switches = RunOptionSwitches(syncToHsync: true);
    await controller().setRunOptionSwitches(switches);
    await controller().setSoundChannelVolume(SoundChannel.keyboardBeep, 0.25);

    await controller().shutdown();
    // createSessionはsetUpのクロージャーが参照する`session`変数を
    // 差し替えるだけで、次のlaunchから新しいFakeへ切り替わる。
    session = FakeEmulatorSession();
    await controller().launch();

    expect(session.setSpeedMultiplierCalls, [SpeedMultiplier.x2]);
    expect(session.setFullSpeedCalls, [true]);
    expect(session.setCpuTypeCalls, [CpuType.slow]);
    expect(session.setRunOptionSwitchesCalls, [switches]);
    // 既定と異なるチャンネル（keyboardBeep）だけを再送する。
    expect(session.setSoundChannelVolumeCalls, [
      (SoundChannel.keyboardBeep, 0.25),
    ]);
  });

  test('AUD-04 fddMechanismチャンネルの音量はコアへ送らずホスト側合成器へ送る', () async {
    await controller().setSoundChannelVolume(SoundChannel.fddMechanism, 0.3);

    expect(session.setFddMechanicalSoundVolumeCalls, [0.3]);
    expect(session.setSoundChannelVolumeCalls, isEmpty);
    expect(state().soundVolumes.fddMechanism, 0.3);
  });

  test('AUD-04 fddMechanismの音量も次回launch時にホスト側合成器へ再適用される', () async {
    await controller().setSoundChannelVolume(SoundChannel.fddMechanism, 0.4);

    await controller().shutdown();
    session = FakeEmulatorSession();
    await controller().launch();

    expect(session.setFddMechanicalSoundVolumeCalls, [0.4]);
    expect(session.setSoundChannelVolumeCalls, isEmpty);
  });

  test('AUD-04 機構音の有効・無効は起動中ならホスト側へ即時に送り、状態も更新する', () async {
    controller().setFddMechanicalSoundEnabled(false);

    expect(session.setFddMechanicalSoundEnabledCalls, [false]);
    expect(state().fddMechanicalSoundEnabled, isFalse);
  });

  test('AUD-04 機構音の無効設定は次回launch時に再適用される', () async {
    controller().setFddMechanicalSoundEnabled(false);

    await controller().shutdown();
    session = FakeEmulatorSession();
    await controller().launch();

    expect(session.setFddMechanicalSoundEnabledCalls, [false]);
  });

  test('AUD-04 launch直後は既定値（有効）どおりなら送らない', () async {
    await controller().shutdown();
    session = FakeEmulatorSession();
    await controller().launch();

    expect(session.setFddMechanicalSoundEnabledCalls, isEmpty);
  });

  test('AUD-06 startRecordingは保存先を取得してセッションへ渡し、状態を更新する', () async {
    await controller().startRecording();

    expect(appDataPaths.musicFilePathCallCount, 1);
    expect(session.startRecordingCalls, hasLength(1));
    expect(session.startRecordingCalls.single, contains('.wav'));
    expect(state().isRecording, isTrue);
  });

  test('AUD-06 保存先が取得できなければ何もしない', () async {
    appDataPaths.musicPath = null;

    await controller().startRecording();

    expect(session.startRecordingCalls, isEmpty);
    expect(state().isRecording, isFalse);
  });

  test('AUD-06 セッション側が開けなければ状態を変えない', () async {
    session.startRecordingResult = false;

    await controller().startRecording();

    expect(session.startRecordingCalls, hasLength(1));
    expect(state().isRecording, isFalse);
  });

  test('AUD-06 既に録音中ならstartRecordingは何もしない', () async {
    await controller().startRecording();
    await controller().startRecording();

    expect(session.startRecordingCalls, hasLength(1));
  });

  test('AUD-06 stopRecordingでセッションを止め、状態をfalseへ戻す', () async {
    await controller().startRecording();

    await controller().stopRecording();

    expect(session.stopRecordingCallCount, 1);
    expect(state().isRecording, isFalse);
  });

  test('AUD-06 録音中でなければstopRecordingは何もしない', () async {
    await controller().stopRecording();

    expect(session.stopRecordingCallCount, 0);
  });

  test('AUD-06 shutdownは録音中ならセッションのstopRecordingを呼ぶ', () async {
    await controller().startRecording();

    await controller().shutdown();

    expect(session.stopRecordingCallCount, 1);
    expect(state().isRecording, isFalse);
  });

  test('INP-03 startAutoKeyはクリップボードを取得し状態を更新する', () async {
    _setClipboardText('ka');

    await controller().startAutoKey();

    expect(state().isAutoKeying, isTrue);
    await controller().stopAutoKey();
  });

  test('INP-03 クリップボードが空/nullなら何もしない', () async {
    _setClipboardText(null);

    await controller().startAutoKey();

    expect(state().isAutoKeying, isFalse);
    expect(session.keyEvents, isEmpty);
  });

  test('INP-03 打てる文字が1つもなければ状態はfalseのまま', () async {
    _setClipboardText('漢字');

    await controller().startAutoKey();

    expect(state().isAutoKeying, isFalse);
    expect(session.keyEvents, isEmpty);
  });

  test('INP-03 既に自動キー入力中ならstartAutoKeyは何もしない', () async {
    _setClipboardText('ka');
    await controller().startAutoKey();

    await controller().startAutoKey();

    expect(state().isAutoKeying, isTrue);
    await controller().stopAutoKey();
  });

  test('INP-03 stopAutoKeyで止め、状態をfalseへ戻す', () async {
    _setClipboardText('ka');
    await controller().startAutoKey();

    await controller().stopAutoKey();

    expect(state().isAutoKeying, isFalse);
  });

  test('INP-03 自動キー入力中でなければstopAutoKeyは何もしない', () async {
    await controller().stopAutoKey();

    expect(state().isAutoKeying, isFalse);
  });

  test('INP-03 setRomajiToKanaは状態を更新する', () {
    expect(state().romajiToKana, isFalse);

    controller().setRomajiToKana(true);

    expect(state().romajiToKana, isTrue);
  });

  test('INP-03 shutdownは自動キー入力中ならエンジンを止める', () async {
    _setClipboardText('ka');
    await controller().startAutoKey();
    expect(state().isAutoKeying, isTrue);

    await controller().shutdown();

    expect(state().isAutoKeying, isFalse);
  });

  test('INP-03 ローマ字かな変換ON中は英字キーの実入力をローマ字→かな変換して打鍵する'
      '（KANAロックの一時トグルつき、通常経路には乗せない）', () {
    fakeAsync((async) {
      final liveSession = FakeEmulatorSession();
      final liveProvider =
          NotifierProvider<EmulatorController, EmulatorViewState>(
            () => EmulatorController(
              appDataPaths: FakeAppDataPaths(),
              externalFileAccess: FakeExternalFileAccess(),
              cacheWorkspace: FakeCacheWorkspace(),
              preferences: FakePreferencesStore(),
              createSession: ({
                required String homeDir,
                String? romDir,
                BootMode bootMode = BootMode.basic,
              }) => liveSession,
            ),
          );
      final liveContainer = ProviderContainer();
      final liveController = liveContainer.read(liveProvider.notifier);
      liveController.launch();
      async.flushMicrotasks();

      liveController.setRomajiToKana(true);
      // "ka" → カ（清音）。1文字目は確定しないためバッファに保持される。
      liveController.handleKeyDown(PhysicalKeyboardKey.keyK, character: 'k');
      async.flushMicrotasks();
      expect(liveSession.keyEvents, isEmpty);

      liveController.handleKeyDown(PhysicalKeyboardKey.keyA, character: 'a');
      async.elapse(const Duration(milliseconds: 400));

      expect(liveSession.keyEvents, [
        Win32Vk.kana,
        -Win32Vk.kana, // KANAロックON
        Win32Vk.keyA + 19,
        -(Win32Vk.keyA + 19), // 「カ」
        Win32Vk.kana,
        -Win32Vk.kana, // 開始時（OFF）へ復帰
      ]);

      // 横取りした物理キーのkeyUpは、対応するkey_downを送っていないため
      // key_upも送らない（合成した打鍵は上のシーケンスで既に上げている）。
      liveController.handleKeyUp(PhysicalKeyboardKey.keyK);
      liveController.handleKeyUp(PhysicalKeyboardKey.keyA);
      async.flushMicrotasks();
      expect(liveSession.keyEvents, hasLength(6));

      liveContainer.dispose();
      async.flushMicrotasks();
    });
  });

  test('INP-03 開始時すでにKANAロックがONなら、ライブ変換はトグルせずかな文字だけを打鍵する', () {
    fakeAsync((async) {
      final liveSession = FakeEmulatorSession();
      final liveProvider =
          NotifierProvider<EmulatorController, EmulatorViewState>(
            () => EmulatorController(
              appDataPaths: FakeAppDataPaths(),
              externalFileAccess: FakeExternalFileAccess(),
              cacheWorkspace: FakeCacheWorkspace(),
              preferences: FakePreferencesStore(),
              createSession: ({
                required String homeDir,
                String? romDir,
                BootMode bootMode = BootMode.basic,
              }) => liveSession,
            ),
          );
      final liveContainer = ProviderContainer();
      final liveController = liveContainer.read(liveProvider.notifier);
      liveController.launch();
      async.flushMicrotasks();
      // LEDが実際にKANAロックON（利用者が手動で既にKANAロックしている、
      // またはLED通知が実状態を正しく反映している場合）を報告している
      // ものとする。
      liveSession.emit(const LedStateChanged(LedState(kana: true)));
      async.flushMicrotasks();

      liveController.setRomajiToKana(true);
      liveController.handleKeyDown(PhysicalKeyboardKey.keyK, character: 'k');
      liveController.handleKeyDown(PhysicalKeyboardKey.keyA, character: 'a');
      async.elapse(const Duration(milliseconds: 400));

      // 開始時からKANAロックONのため、トグルは一切送らない
      // （`AutoKeyEngine`のKANA区間境界トグルと同じ規則）。
      expect(liveSession.keyEvents, [
        Win32Vk.keyA + 19,
        -(Win32Vk.keyA + 19), // 「カ」
      ]);

      liveContainer.dispose();
      async.flushMicrotasks();
    });
  });

  test('INP-03 ローマ字かな変換OFF中は英字キーを通常どおりそのまま打鍵する（回帰確認）', () {
    fakeAsync((async) {
      final liveSession = FakeEmulatorSession();
      final liveProvider =
          NotifierProvider<EmulatorController, EmulatorViewState>(
            () => EmulatorController(
              appDataPaths: FakeAppDataPaths(),
              externalFileAccess: FakeExternalFileAccess(),
              cacheWorkspace: FakeCacheWorkspace(),
              preferences: FakePreferencesStore(),
              createSession: ({
                required String homeDir,
                String? romDir,
                BootMode bootMode = BootMode.basic,
              }) => liveSession,
            ),
          );
      final liveContainer = ProviderContainer();
      final liveController = liveContainer.read(liveProvider.notifier);
      liveController.launch();
      async.flushMicrotasks();

      liveController.handleKeyDown(PhysicalKeyboardKey.keyK, character: 'k');
      async.flushMicrotasks();
      liveController.handleKeyUp(PhysicalKeyboardKey.keyK);
      async.flushMicrotasks();

      expect(liveSession.keyEvents, isNotEmpty);
      expect(liveSession.keyEvents.first, isPositive); // keyDownがすぐ届く

      liveContainer.dispose();
      async.flushMicrotasks();
    });
  });

  test('launch直後は既定値どおりの実行設定を送らない（無駄な往復を避ける）', () async {
    await controller().shutdown();
    session = FakeEmulatorSession();
    await controller().launch();

    expect(session.setSpeedMultiplierCalls, isEmpty);
    expect(session.setFullSpeedCalls, isEmpty);
    expect(session.setCpuTypeCalls, isEmpty);
    expect(session.setRunOptionSwitchesCalls, isEmpty);
    expect(session.setSoundChannelVolumeCalls, isEmpty);
  });

  test('停止後も実行設定の選択はstateに残る（メニュー表示とのずれを防ぐ）', () async {
    await controller().setSpeedMultiplier(SpeedMultiplier.x4);
    await controller().setFullSpeed(true);
    await controller().setCpuType(CpuType.slow);
    await controller().setSoundChannelVolume(SoundChannel.opnPsg, 0.75);

    await controller().shutdown();

    expect(state().speedMultiplier, SpeedMultiplier.x4);
    expect(state().fullSpeed, isTrue);
    expect(state().cpuType, CpuType.slow);
    expect(state().soundVolumes.opnPsg, 0.75);
    expect(state().isRunning, isFalse);
  });

  test('FDD-01 挿入は原本を作業領域へ複製し、複製先パスをコアへ渡す', () async {
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/GAME.D88',
      displayName: 'GAME.D88',
    );

    await controller().insertFdd(0);

    expect(cacheWorkspace.createSessionWorkspaceCallCount, 1);
    expect(cacheWorkspace.handle.importedFileNames, ['fd0-GAME.D88']);
    expect(session.insertCalls, hasLength(1));
    final (drive, imagePath, _) = session.insertCalls.single;
    expect(drive, 0);
    expect(imagePath, '${cacheWorkspace.handle.nativePath}/fd0-GAME.D88');
    expect(state().fddMedia[0], 'GAME.D88');
  });

  test('FDD-01 選択をキャンセルすると何も起きない', () async {
    externalFileAccess.nextPickResult = null;

    await controller().insertFdd(0);

    expect(session.insertCalls, isEmpty);
    expect(state().fddMedia, isEmpty);
  });

  test('FDD-01 挿入済みドライブへ再度挿入すると、先に排出してから入れ替える', () async {
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/GAME.D88',
      displayName: 'GAME.D88',
    );
    await controller().insertFdd(0);

    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/OTHER.D88',
      displayName: 'OTHER.D88',
    );
    await controller().insertFdd(0);

    expect(session.insertCalls, hasLength(2));
    expect(session.ejectCalls, [0]);
    expect(cacheWorkspace.handle.exportCalls, [
      ('fd0-GAME.D88', '/Volumes/USB/GAME.D88'),
    ]);
    expect(state().fddMedia[0], 'OTHER.D88');
  });

  test('FDD-01 コマンドが失敗したらアクセス権を返し状態を更新しない', () async {
    session.nextInsertError = EmulatorErrorCode.invalidArgument;
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/GAME.D88',
      displayName: 'GAME.D88',
    );

    await controller().insertFdd(0);

    expect(state().fddMedia, isEmpty);
  });

  test('FDD-01 排出は完了を待ってから作業領域の複製を原本へ原子的に書き戻す', () async {
    final resource = FakeExternalResource(
      '/Volumes/USB/GAME.D88',
      displayName: 'GAME.D88',
    );
    externalFileAccess.nextPickResult = resource;
    await controller().insertFdd(0);

    await controller().ejectFdd(0);

    expect(session.ejectCalls, [0]);
    expect(cacheWorkspace.handle.exportCalls, [
      ('fd0-GAME.D88', '/Volumes/USB/GAME.D88'),
    ]);
    expect(resource.releaseCallCount, 1);
    expect(state().fddMedia, isEmpty);
  });

  test('FDD-06 書込み保護・タイミング補正・CRC無視は起動中ならコアへ即時に送り、状態も更新する', () async {
    await controller().setFddWriteProtect(0, true);
    await controller().setFddTiming(0, true);
    await controller().setFddCrcCheck(0, true);

    expect(session.setFddWriteProtectCalls, [(0, true)]);
    expect(session.setFddTimingCalls, [(0, true)]);
    expect(session.setFddCrcCheckCalls, [(0, true)]);
    expect(
      state().fddDriveSettings[0],
      const FddDriveSettings(
        writeProtected: true,
        correctTiming: true,
        ignoreCrc: true,
      ),
    );
  });

  test('FDD-06 タイミング補正・CRC無視は次回launch時に新しいセッションへ再適用される', () async {
    await controller().setFddTiming(1, true);
    await controller().setFddCrcCheck(1, true);
    await controller().shutdown();
    session = FakeEmulatorSession();

    await controller().launch();

    expect(session.setFddTimingCalls, [(1, true)]);
    expect(session.setFddCrcCheckCalls, [(1, true)]);
  });

  test('FDD-06 書込み保護は媒体自身が持つ状態のため、launch時には再適用しない', () async {
    await controller().setFddWriteProtect(1, true);
    await controller().shutdown();
    session = FakeEmulatorSession();

    await controller().launch();

    expect(session.setFddWriteProtectCalls, isEmpty);
  });

  test('FDD-06 挿入すると書込み保護の表示は媒体自身が持つ実際値になる', () async {
    session.fddWriteProtectByDrive[0] = true;
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/PROTECTED.D88',
      displayName: 'PROTECTED.D88',
    );

    await controller().insertFdd(0);

    expect(state().fddDriveSettings[0]?.writeProtected, isTrue);
  });

  test('FDD-06 排出すると書込み保護の表示はfalseへ戻る', () async {
    session.fddWriteProtectByDrive[0] = true;
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/PROTECTED.D88',
      displayName: 'PROTECTED.D88',
    );
    await controller().insertFdd(0);

    await controller().ejectFdd(0);

    expect(state().fddDriveSettings[0]?.writeProtected, isFalse);
  });

  test('FDD-06 前のディスクの保護状態を持ち越さず、次のディスクの実際値に従う', () async {
    session.fddWriteProtectByDrive[0] = true;
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/PROTECTED.D88',
      displayName: 'PROTECTED.D88',
    );
    await controller().insertFdd(0);

    session.fddWriteProtectByDrive[0] = false;
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/OTHER.D88',
      displayName: 'OTHER.D88',
    );
    await controller().insertFdd(0);

    expect(state().fddDriveSettings[0]?.writeProtected, isFalse);
  });

  test('FDD-05 空ディスクを作成すると通常の挿入フローに合流する', () async {
    externalFileAccess.nextSaveLocationResult = FakeExternalResource(
      '/Volumes/USB/NEW.D88',
      displayName: 'NEW.D88',
    );

    await controller().insertBlankFdd(0, FddMediaType.d2dd);

    expect(session.createBlankFddCalls, [
      (FddMediaType.d2dd, '/Volumes/USB/NEW.D88'),
    ]);
    expect(session.insertCalls, hasLength(1));
    expect(state().fddMedia[0], 'NEW.D88');
    expect(
      externalFileAccess.pickSaveLocationSuggestedNames,
      contains('blank-2dd.d88'),
    );
  });

  test('FDD-05 保存先の選択をキャンセルすると何も起きない', () async {
    externalFileAccess.nextSaveLocationResult = null;

    await controller().insertBlankFdd(0, FddMediaType.d2);

    expect(session.createBlankFddCalls, isEmpty);
    expect(session.insertCalls, isEmpty);
  });

  test('FDD-04 バンク切替は排出して書き戻してから同じ作業コピーを新バンクで再挿入する', () async {
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/GAME.D88',
      displayName: 'GAME.D88',
    );
    await controller().insertFdd(0);
    session.fddBankInfoByDrive[0] = (bankNum: 2, curBank: 1);

    await controller().insertFddBank(0, 1);

    expect(session.ejectCalls, [0]);
    expect(session.insertCalls, hasLength(2));
    final (drive, imagePath, bank) = session.insertCalls[1];
    expect(drive, 0);
    expect(imagePath, '${cacheWorkspace.handle.nativePath}/fd0-GAME.D88');
    expect(bank, 1);
    // 原本を再選択せず、同じ作業コピーへ書き戻してから再挿入する。
    expect(cacheWorkspace.handle.exportCalls, [
      ('fd0-GAME.D88', '/Volumes/USB/GAME.D88'),
    ]);
    expect(state().fddBankNum[0], 2);
    expect(state().fddCurBank[0], 1);
  });

  test('FDD-09 Save Asは原本に触れず、選択先へ保存してから挿入したままにする', () async {
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/GAME.TD0',
      displayName: 'GAME.TD0',
    );
    await controller().insertFdd(0);
    externalFileAccess.nextSaveLocationResult = FakeExternalResource(
      '/Volumes/USB/SAVED.D88',
      displayName: 'SAVED.D88',
    );

    await controller().saveFddAs(0);

    expect(session.ejectCalls, [0]);
    expect(cacheWorkspace.handle.exportCalls, [
      ('fd0-GAME.TD0', '/Volumes/USB/SAVED.D88'),
    ]);
    // 原本(GAME.TD0)へは一度もexportAtomicしていない。
    expect(
      cacheWorkspace.handle.exportCalls.any(
        (call) => call.$2 == '/Volumes/USB/GAME.TD0',
      ),
      isFalse,
    );
    expect(session.insertCalls, hasLength(2));
    expect(state().fddMedia[0], isNotNull);
  });

  test('FDD-07 挿入した媒体は最近使ったファイルへ記録され、再選択できる', () async {
    final resource = FakeExternalResource(
      '/Volumes/USB/GAME.D88',
      displayName: 'GAME.D88',
    );
    externalFileAccess.nextPickResult = resource;
    await controller().insertFdd(0);
    await controller().ejectFdd(0);

    expect(state().fddRecentFiles[0], [
      (token: '/Volumes/USB/GAME.D88', displayName: 'GAME.D88'),
    ]);

    externalFileAccess.resolveResultByToken['/Volumes/USB/GAME.D88'] =
        FakeExternalResource('/Volumes/USB/GAME.D88', displayName: 'GAME.D88');
    await controller().insertFddFromRecent(0, '/Volumes/USB/GAME.D88');

    expect(externalFileAccess.resolveCalls, ['/Volumes/USB/GAME.D88']);
    expect(state().fddMedia[0], 'GAME.D88');
  });

  test('FDD-07 失効したトークンは履歴から外す', () async {
    await controller().insertFddFromRecent(0, 'stale-token');

    expect(session.insertCalls, isEmpty);
  });

  test('FDD-07 履歴は次回launch時にも保持される', () async {
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/GAME.D88',
      displayName: 'GAME.D88',
    );
    await controller().insertFdd(0);
    await controller().shutdown();
    session = FakeEmulatorSession();

    await controller().launch();

    expect(state().fddRecentFiles[0], [
      (token: '/Volumes/USB/GAME.D88', displayName: 'GAME.D88'),
    ]);
  });

  test('FDD-07 履歴を消去できる', () async {
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/GAME.D88',
      displayName: 'GAME.D88',
    );
    await controller().insertFdd(0);

    await controller().clearRecentFiles(0);

    expect(state().fddRecentFiles[0], isEmpty);
  });

  test('FDD-01 未挿入のドライブを排出しても何もしない', () async {
    await controller().ejectFdd(1);

    expect(session.ejectCalls, isEmpty);
    expect(cacheWorkspace.handle.exportCalls, isEmpty);
  });

  test('アクセス状態の通知は最終確認時刻として反映する', () async {
    session.emit(const MediaAccessChanged({0}));
    await Future<void>.delayed(Duration.zero);

    expect(state().fddLastAccessed.containsKey(0), isTrue);
  });

  test('shutdownは挿入中のFDDを排出してから終了する', () async {
    externalFileAccess.nextPickResult = FakeExternalResource(
      '/Volumes/USB/GAME.D88',
      displayName: 'GAME.D88',
    );
    await controller().insertFdd(0);

    await controller().shutdown();

    expect(session.ejectCalls, [0]);
    expect(cacheWorkspace.handle.exportCalls, hasLength(1));
    expect(cacheWorkspace.handle.disposed, isTrue);
    expect(state().session, SessionState.stopped);
  });

  test('View/Core FPSは1秒間隔の差分から求める（design.md 12.4）', () {
    fakeAsync((async) {
      final fpsSession = FakeEmulatorSession();
      final fpsProvider =
          NotifierProvider<EmulatorController, EmulatorViewState>(
            () => EmulatorController(
              appDataPaths: FakeAppDataPaths(),
              externalFileAccess: FakeExternalFileAccess(),
              cacheWorkspace: FakeCacheWorkspace(),
              preferences: FakePreferencesStore(),
              createSession: ({
                required String homeDir,
                String? romDir,
                BootMode bootMode = BootMode.basic,
              }) => fpsSession,
            ),
          );
      final fpsContainer = ProviderContainer();
      fpsContainer.read(fpsProvider.notifier).launch();
      async.flushMicrotasks();

      // 1回目のtickは基準値を記録するだけで、まだ差分を出さない。
      async.elapse(const Duration(seconds: 1));
      expect(fpsContainer.read(fpsProvider).coreFps, 0);

      fpsSession.stats = const EmulatorStats(
        framesRun: 60,
        commandsAccepted: 0,
        commandsRejected: 0,
        eventsDropped: 0,
        vmAccessViolations: 0,
        framesPublished: 55,
        framesDropped: 0,
        audioFramesProduced: 0,
        audioUnderrunFrames: 0,
        audioOverrunFrames: 0,
      );
      async.elapse(const Duration(seconds: 1));

      final fpsState = fpsContainer.read(fpsProvider);
      expect(fpsState.coreFps, 60);
      expect(fpsState.viewFps, 55);

      fpsContainer.dispose();
      async.flushMicrotasks();
    });
  });
}
