import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../emulator/emulator_error.dart';
import '../../emulator/emulator_event.dart';
import '../../emulator/emulator_session.dart';
import '../../emulator/emulator_session_factory.dart';
import '../../emulator/emulator_stats.dart';
import '../../emulator/session_state.dart';
import '../../platform/persistence/app_data_paths.dart';
import '../../platform/persistence/cache_workspace.dart';
import '../../platform/persistence/external_file_access.dart';
import '../display/screen_fit.dart';
import 'emulator_state.dart';
import 'input/keyboard_key_map.dart';

/// native container（D88/D77/D8E/1DD）だけを対象にする（design.md 16.1）。
///
/// converted/raw形式（TD0/IMD/DSK/NFD/FDIなど）はM3 8.1で扱う。
const fddNativeContainerExtensions = ['d88', 'd77', 'd8e', '1dd'];

/// エミュレーターの起動と画面の受け取りを持つController。
///
/// 高頻度データは通さない。画素はネイティブ側がTextureへ直接渡し、
/// ここが持つのはTexture IDと解像度だけである（design.md 16.1）。
class EmulatorController extends Notifier<EmulatorViewState> {
  EmulatorController({
    required this.appDataPaths,
    required this.createSession,
    required this.externalFileAccess,
    required this.cacheWorkspace,
  });

  final AppDataPaths appDataPaths;
  final EmulatorSessionFactory createSession;

  /// FDDの原本を選ばせ、アクセス権を確保する（design.md 11.2、16.1）。
  final ExternalFileAccess externalFileAccess;

  /// 挿入中の原本の複製を置くセッション作業領域（design.md 11.2、16.1）。
  final CacheWorkspace cacheWorkspace;

  EmulatorSession? _session;
  StreamSubscription<EmulatorEvent>? _events;

  WorkspaceHandle? _workspace;
  final Map<int, _FddSlot> _fddSlots = {};
  final Map<int, Completer<EmulatorErrorCode?>> _pendingCommands = {};

  /// ステータスバーのView/Core FPS（design.md 12.4）を出すための定期観測。
  ///
  /// `EmulatorStats`は累積カウンターのため、ここで前回値との差分を
  /// 一定間隔で取ってレートへ変換する。高頻度データではないので
  /// Riverpodのstateへ載せてよい（design.md 4.3）。
  static const _statsPollInterval = Duration(seconds: 1);
  Timer? _statsTimer;
  EmulatorStats? _lastStats;

  /// 現在押下中のキー（INP-01）。
  ///
  /// 高頻度なキー入力そのものはRiverpodのstateへ載せず、ここに保つ。
  /// OSのキーリピートによる二重押下の除去と、フォーカス喪失時の
  /// 全解放（design.md 8）に使う。
  final Set<PhysicalKeyboardKey> _pressedKeys = {};

  @override
  EmulatorViewState build() {
    ref.onDispose(_teardown);
    return const EmulatorViewState();
  }

  /// コアを起動して画面をつなぐ。すでに動いていれば何もしない。
  Future<void> launch({BootMode bootMode = BootMode.basic}) async {
    if (_session != null) {
      return;
    }
    state = state.copyWith(
      session: SessionState.starting,
      clearFailure: true,
      bootMode: bootMode,
    );
    try {
      final homeDir = await appDataPaths.coreHomeDirectoryPath();
      final romDir = await appDataPaths.romsDirectoryPath();
      final session = createSession(
        homeDir: homeDir,
        romDir: romDir,
        bootMode: bootMode,
      );
      _session = session;
      _events = session.events.listen(_onEvent);
      await session.start();
      final textureId = await session.attachVideoTexture();
      state = state.copyWith(session: session.state, textureId: textureId);
      _lastStats = null;
      _statsTimer = Timer.periodic(_statsPollInterval, (_) => _pollStats());
    } on Object catch (error) {
      state = state.copyWith(
        session: SessionState.failed,
        failureMessage: '$error',
      );
      await _teardown();
    }
  }

  /// コアを止めて画面を外す。
  ///
  /// 挿入中のFDDがあれば、書き戻しを終えてから止める。停止後は
  /// `CacheWorkspace`の内容が失われるため（design.md 11.2）、ここで
  /// 排出しない限り未反映のまま消える。
  Future<void> shutdown() async {
    for (final drive in _fddSlots.keys.toList()) {
      await ejectFdd(drive);
    }
    await _teardown();
    state = const EmulatorViewState();
  }

  /// リセットを投入する。
  Future<void> reset(ResetKind kind) async {
    await _session?.reset(kind);
  }

  /// 表示領域への合わせ方を変える（VID-02）。
  void setFit(ScreenFit fit) {
    state = state.copyWith(fit: fit);
  }

  /// キーが押された（INP-01）。
  ///
  /// OSのキーリピートは同じ[physicalKey]を離さないまま繰り返し通知するため、
  /// 押下集合にすでにあれば境界で捨てる。コアの`key_down`へ二重に送らない。
  void handleKeyDown(
    PhysicalKeyboardKey physicalKey, {
    LogicalKeyboardKey? logicalKey,
  }) {
    final session = _session;
    if (session == null || !_pressedKeys.add(physicalKey)) {
      return;
    }
    final vk = vkFromKeyEvent(physicalKey: physicalKey, logicalKey: logicalKey);
    if (vk != null) {
      unawaited(session.keyDown(vk));
    }
  }

  /// キーが離された（INP-01）。
  void handleKeyUp(
    PhysicalKeyboardKey physicalKey, {
    LogicalKeyboardKey? logicalKey,
  }) {
    final session = _session;
    if (session == null || !_pressedKeys.remove(physicalKey)) {
      return;
    }
    final vk = vkFromKeyEvent(physicalKey: physicalKey, logicalKey: logicalKey);
    if (vk != null) {
      unawaited(session.keyUp(vk));
    }
  }

  /// 押下中のキーをすべて解放する。
  ///
  /// フォーカス喪失時に呼ぶ（design.md 8）。離す操作を見せないままウィンドウ
  /// を切り替えると、コア側でキーが押されっぱなしになる。
  void releaseAllKeys() {
    final session = _session;
    final keys = _pressedKeys.toList();
    _pressedKeys.clear();
    if (session == null) {
      return;
    }
    for (final key in keys) {
      final vk = vkFromKeyEvent(physicalKey: key);
      if (vk != null) {
        unawaited(session.keyUp(vk));
      }
    }
  }

  /// FD1(0)/FD2(1)へ利用者が選んだ媒体を挿入する（FDD-01）。
  ///
  /// 原本は`CacheWorkspace`のセッション作業領域へ複製し、コアには
  /// 複製先のパスだけを渡す（design.md 9.1、16.1）。対象ドライブへ
  /// すでに挿入済みなら何もしない。
  Future<void> insertFdd(int drive) async {
    final session = _session;
    if (session == null || _fddSlots.containsKey(drive)) {
      return;
    }
    final resource = await externalFileAccess.pickFile(
      allowedExtensions: fddNativeContainerExtensions,
    );
    if (resource == null) {
      return;
    }
    try {
      final workspace = _workspace ??= await cacheWorkspace
          .createSessionWorkspace();
      final fileName = 'fd$drive-${resource.displayName}';
      final workspacePath = await resource.withAccess(
        (nativePath) => workspace.importCopy(nativePath, fileName: fileName),
      );
      final commandId = await session.insertFdd(drive, workspacePath);
      final error = await _awaitCommand(commandId);
      if (error != null) {
        await resource.release();
        state = state.copyWith(failureMessage: '$error');
        return;
      }
      _fddSlots[drive] = _FddSlot(
        resource: resource,
        workspaceFileName: fileName,
      );
      state = state.copyWith(
        fddMedia: {...state.fddMedia, drive: resource.displayName},
      );
    } on Object catch (error) {
      await resource.release();
      state = state.copyWith(failureMessage: '$error');
    }
  }

  /// FD1(0)/FD2(1)から媒体を排出する（FDD-01）。
  ///
  /// コアが排出を終えたことを確認してから、作業領域の複製を原本へ
  /// 原子的に書き戻す（design.md 16.1）。未挿入のドライブは何もしない。
  Future<void> ejectFdd(int drive) async {
    final session = _session;
    final slot = _fddSlots[drive];
    if (session == null || slot == null) {
      return;
    }
    final commandId = await session.ejectFdd(drive);
    final error = await _awaitCommand(commandId);
    if (error != null) {
      state = state.copyWith(failureMessage: '$error');
      return;
    }
    final workspace = _workspace;
    if (workspace != null) {
      await slot.resource.withAccess(
        (nativePath) =>
            workspace.exportAtomic(slot.workspaceFileName, nativePath),
      );
    }
    await slot.resource.release();
    _fddSlots.remove(drive);
    final media = {...state.fddMedia}..remove(drive);
    state = state.copyWith(fddMedia: media);
  }

  /// 前回の観測との差分からView/Core FPSを求める（design.md 12.4）。
  void _pollStats() {
    final session = _session;
    if (session == null) {
      return;
    }
    final stats = session.readStats();
    final last = _lastStats;
    _lastStats = stats;
    if (last == null) {
      return;
    }
    final seconds = _statsPollInterval.inMilliseconds / 1000;
    state = state.copyWith(
      viewFps: (stats.framesPublished - last.framesPublished) / seconds,
      coreFps: (stats.framesRun - last.framesRun) / seconds,
    );
  }

  /// [commandId]の[CommandCompleted]を待つ。成功ならnull、失敗ならエラー。
  Future<EmulatorErrorCode?> _awaitCommand(int commandId) {
    final completer = Completer<EmulatorErrorCode?>();
    _pendingCommands[commandId] = completer;
    return completer.future;
  }

  void _onEvent(EmulatorEvent event) {
    switch (event) {
      case LifecycleChanged(:final state):
        this.state = this.state.copyWith(session: state);
      case ScreenModeChanged(:final width, :final height):
        state = state.copyWith(frameWidth: width, frameHeight: height);
      case LedStateChanged(:final state):
        this.state = this.state.copyWith(ledState: state);
      case EmulatorErrorOccurred(:final code):
        state = state.copyWith(failureMessage: '$code');
      case CommandCompleted(:final commandId, :final error):
        _pendingCommands.remove(commandId)?.complete(error);
      case MediaAccessChanged(:final accessedDrives):
        final now = DateTime.now();
        state = state.copyWith(
          fddLastAccessed: {
            ...state.fddLastAccessed,
            for (final drive in accessedDrives) drive: now,
          },
        );
      default:
        break;
    }
  }

  Future<void> _teardown() async {
    // Timerの取消しは同期的に真っ先に行う。`ref.onDispose`はこの関数を
    // 待たないため、最初のawaitより後ろに置くとdispose直後にまだ
    // 生き残ってしまう（試験のFlutter testはpending timerを許さない）。
    _statsTimer?.cancel();
    _statsTimer = null;
    _lastStats = null;
    final session = _session;
    _session = null;
    await _events?.cancel();
    _events = null;
    _pressedKeys.clear();
    _pendingCommands.clear();
    // 排出（design.md 16.1の書き戻し）を経ずに残ったスロットは
    // `shutdown()`を通らなかった場合（例: `dispose`のみ）にありうる。
    // `CacheWorkspace`は消失前提のため、書き戻さずアクセス権だけ返す。
    for (final slot in _fddSlots.values) {
      await slot.resource.release();
    }
    _fddSlots.clear();
    final workspace = _workspace;
    _workspace = null;
    if (workspace != null) {
      await workspace.dispose();
    }
    if (session == null) {
      return;
    }
    // 終了順序は design.md 5.1。Texture解放はセッション破棄より先で、
    // dispose の中で行われる。
    await session.stop();
    await session.dispose();
  }
}

class _FddSlot {
  _FddSlot({required this.resource, required this.workspaceFileName});

  final ExternalResource resource;
  final String workspaceFileName;
}
