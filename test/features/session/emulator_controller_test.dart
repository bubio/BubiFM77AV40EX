import 'package:bubi_fm77av40ex/emulator/emulator_error.dart';
import 'package:bubi_fm77av40ex/emulator/emulator_event.dart';
import 'package:bubi_fm77av40ex/emulator/emulator_stats.dart';
import 'package:bubi_fm77av40ex/emulator/session_state.dart';
import 'package:bubi_fm77av40ex/features/session/emulator_controller.dart';
import 'package:bubi_fm77av40ex/features/session/emulator_state.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// FDD挿入・排出（design.md 16.1）の検査。原本は複製してからコアへ渡し、
/// 排出完了を待ってから作業領域を原本へ書き戻すことをFakeで確かめる。
void main() {
  late FakeEmulatorSession session;
  late FakeExternalFileAccess externalFileAccess;
  late FakeCacheWorkspace cacheWorkspace;
  late ProviderContainer container;
  late NotifierProvider<EmulatorController, EmulatorViewState> provider;

  setUp(() async {
    session = FakeEmulatorSession();
    externalFileAccess = FakeExternalFileAccess();
    cacheWorkspace = FakeCacheWorkspace();
    provider = NotifierProvider<EmulatorController, EmulatorViewState>(
      () => EmulatorController(
        appDataPaths: FakeAppDataPaths(),
        externalFileAccess: externalFileAccess,
        cacheWorkspace: cacheWorkspace,
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

  test('SYS-04 bootModeを渡さないリセットはsetBootModeを呼ばない', () async {
    await controller().reset(ResetKind.special);

    expect(session.setBootModeCalls, isEmpty);
    expect(session.resetCalls, [ResetKind.special]);
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
