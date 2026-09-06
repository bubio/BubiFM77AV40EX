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

  /// 直近に指定されたマスター音量。次回[launch]時にも適用する
  /// （design.md 12.4）。
  double _masterVolume = 1.0;

  /// 直近に指定された実行設定（SYS-03、SYS-05、SYS-06）。
  /// 停止中に変更されても次回[launch]時に適用できるよう覚えておく。
  int _speedMultiplier = SpeedMultiplier.x1;
  bool _fullSpeed = false;
  CpuType _cpuType = CpuType.fast;
  RunOptionSwitches _optionSwitches = const RunOptionSwitches();

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
      session.setVolume(_masterVolume);
      state = state.copyWith(session: session.state, textureId: textureId);
      _lastStats = null;
      _statsTimer = Timer.periodic(_statsPollInterval, (_) => _pollStats());
      // 実行設定は起動が終わってから覚えている値を再適用する。既定値
      // どおりなら何も送らない（新しいコアの初期値と同じであり、
      // 無駄な往復を避ける）。ここで失敗しても、すでに動き出した
      // セッションをfailedへ巻き戻さない（SYS-03、SYS-05、SYS-06は
      // 起動そのものに必須ではないため、外側のtry/catchへ伝えない）。
      try {
        if (_speedMultiplier != SpeedMultiplier.x1) {
          await session.setSpeedMultiplier(_speedMultiplier);
        }
        if (_fullSpeed) {
          await session.setFullSpeed(_fullSpeed);
        }
        if (_cpuType != CpuType.fast) {
          await session.setCpuType(_cpuType);
        }
        if (_optionSwitches != const RunOptionSwitches()) {
          await session.setRunOptionSwitches(_optionSwitches);
        }
        state = state.copyWith(
          speedMultiplier: _speedMultiplier,
          fullSpeed: _fullSpeed,
          cpuType: _cpuType,
          optionSwitches: _optionSwitches,
        );
      } on Object {
        // 起動自体は成功しているため、実行設定の再適用失敗は
        // failureMessageへ出さず、選択値をstateへ反映しないだけにする。
      }
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
    // 実行設定（SYS-03、SYS-05、SYS-06）とマスター音量は次回launch時に
    // 再適用するため覚えたままにする。表示もそれに合わせ、既定値へ
    // 戻さない（メニューの選択表示が実際に覚えている値と食い違うのを
    // 防ぐ）。
    state = EmulatorViewState(
      speedMultiplier: _speedMultiplier,
      fullSpeed: _fullSpeed,
      cpuType: _cpuType,
      optionSwitches: _optionSwitches,
    );
  }

  /// リセットを投入する。
  ///
  /// [bootMode]を渡すと、コアがリセット時に読む`config.boot_mode`
  /// （native/bridge/src/bubi_fm77av.cpp、SYS-04「再起動後に反映できる」）
  /// をリセットの直前に書き換える。`Control > Boot mode`の選択はリセット
  /// までセッションへ伝わらないため、ここで渡さない限り選択が無視される。
  Future<void> reset(ResetKind kind, {BootMode? bootMode}) async {
    final session = _session;
    if (session == null) {
      return;
    }
    if (bootMode != null) {
      await session.setBootMode(bootMode);
    }
    await session.reset(kind);
    if (bootMode != null) {
      state = state.copyWith(bootMode: bootMode);
    }
  }

  /// 表示領域への合わせ方を変える（VID-02）。
  void setFit(ScreenFit fit) {
    state = state.copyWith(fit: fit);
  }

  /// マスター音量を変える（0.0〜1.0、design.md 12.4）。
  ///
  /// 起動中なら即座に反映し、停止中でも次回[launch]時に使う値として
  /// 覚えておく。
  void setVolume(double volume) {
    _masterVolume = volume;
    _session?.setVolume(volume);
  }

  /// CPU速度倍率を変える（SYS-03）。
  ///
  /// コアの`update_config()`経由で即時反映されるため、起動中なら
  /// すぐに切り替わる。停止中は選択を覚えておくだけで、コアには
  /// 送らない（送る宛先セッションがない）。
  Future<void> setSpeedMultiplier(int multiplier) async {
    _speedMultiplier = multiplier;
    state = state.copyWith(speedMultiplier: multiplier);
    await _session?.setSpeedMultiplier(multiplier);
  }

  /// 無制限速度（Full Speed）の有効・無効を変える（SYS-03の「無制限」）。
  ///
  /// 起動中なら即座にCore threadの壁時計待機を止める／再開する。
  Future<void> setFullSpeed(bool enabled) async {
    _fullSpeed = enabled;
    state = state.copyWith(fullSpeed: enabled);
    await _session?.setFullSpeed(enabled);
  }

  /// CPU種別を変える（SYS-05）。起動中ならコアの`update_config()`経由で
  /// 即時反映される。
  Future<void> setCpuType(CpuType type) async {
    _cpuType = type;
    state = state.copyWith(cpuType: type);
    await _session?.setCpuType(type);
  }

  /// サイクルスチール・拡張RAM・HSYNC同期を変える（SYS-06）。
  ///
  /// サイクルスチールとHSYNC同期は起動中なら即時反映される。拡張RAMは
  /// コアがリセット時にしか読まないため、次のリセットまで実際の挙動には
  /// 反映されない（[state]の表示上はここで即座に更新する）。
  Future<void> setRunOptionSwitches(RunOptionSwitches switches) async {
    _optionSwitches = switches;
    state = state.copyWith(optionSwitches: switches);
    await _session?.setRunOptionSwitches(switches);
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
  /// すでに挿入済みでも入れ替えとして扱う。ファイル選択が済んだ後
  /// （＝利用者が入れ替えを確定した後）に、既存の媒体を先に排出
  /// （原本への書き戻しを含む）してから新しい媒体を挿入する。
  Future<void> insertFdd(int drive) async {
    final session = _session;
    if (session == null) {
      return;
    }
    final resource = await externalFileAccess.pickFile(
      allowedExtensions: fddNativeContainerExtensions,
    );
    if (resource == null) {
      return;
    }
    if (_fddSlots.containsKey(drive)) {
      await ejectFdd(drive);
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
