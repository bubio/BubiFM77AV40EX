import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../emulator/emulator_event.dart';
import '../../emulator/emulator_session.dart';
import '../../emulator/emulator_session_factory.dart';
import '../../emulator/session_state.dart';
import '../../platform/persistence/app_data_paths.dart';
import '../display/screen_fit.dart';
import 'emulator_state.dart';
import 'input/keyboard_key_map.dart';

/// エミュレーターの起動と画面の受け取りを持つController。
///
/// 高頻度データは通さない。画素はネイティブ側がTextureへ直接渡し、
/// ここが持つのはTexture IDと解像度だけである（design.md 16.1）。
class EmulatorController extends Notifier<EmulatorViewState> {
  EmulatorController({required this.appDataPaths, required this.createSession});

  final AppDataPaths appDataPaths;
  final EmulatorSessionFactory createSession;

  EmulatorSession? _session;
  StreamSubscription<EmulatorEvent>? _events;

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
    state = state.copyWith(session: SessionState.starting, clearFailure: true);
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
    } on Object catch (error) {
      state = state.copyWith(
        session: SessionState.failed,
        failureMessage: '$error',
      );
      await _teardown();
    }
  }

  /// コアを止めて画面を外す。
  Future<void> shutdown() async {
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
      default:
        break;
    }
  }

  Future<void> _teardown() async {
    final session = _session;
    _session = null;
    await _events?.cancel();
    _events = null;
    _pressedKeys.clear();
    if (session == null) {
      return;
    }
    // 終了順序は design.md 5.1。Texture解放はセッション破棄より先で、
    // dispose の中で行われる。
    await session.stop();
    await session.dispose();
  }
}
