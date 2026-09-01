import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:bubi_fm77av40ex_core/bubi_fm77av40ex_core.dart';
import 'package:ffi/ffi.dart';

import '../../emulator/emulator_error.dart';
import '../../emulator/emulator_event.dart';
import '../../emulator/emulator_session.dart';
import '../../emulator/emulator_stats.dart';
import '../../emulator/session_state.dart';
import 'audio_sink.dart';
import 'native_conversions.dart';
import 'video_texture_attacher.dart';

/// C ABI（native/bridge/）で実装した [EmulatorSession]。
///
/// FFI 呼び出しはコマンド投入とスナップショット読出しに限る（design.md 5.1）。
/// VM を触るのは Core thread だけで、この実体は一度も VM に触れない。
class FfiEmulatorSession implements EmulatorSession {
  FfiEmulatorSession._(
    this._bindings,
    this._handle,
    this._pollInterval,
    this._textures,
    this._audio,
  );

  /// セッションを生成する。
  ///
  /// [homeDir] はコアがアプリケーションデータを置く位置で、
  /// `AppDataPaths` が返す値を渡す。コアの既定に任せると
  /// `~/CommonSourceCodeProject/` を作ってしまい design.md 11.3 と食い違う。
  ///
  /// [pollInterval] はイベントを引き取る間隔。画面描画周期には結合させない。
  /// [romDir] は利用者が選んだROMディレクトリのOSパス。
  /// null なら結線せず、コアは読めるROMがないまま起動を試みる。
  /// ROMの検証は `RomInventory` の責務で、ここでは行わない。
  ///
  /// [textures] は [attachVideoTexture] の実装先。渡さなければ
  /// [attachVideoTexture] は呼べない（`EmulatorErrorCode.invalidState`）。
  /// [audio] は音声出力の実装先。渡さなければ音声は再生されない
  /// （design.md 7 は必須要件だが、`package:flutter`に依存しないここでは
  /// 既定値を持てないため、アプリ側の組み立て（`lib/app/bootstrap.dart`）が
  /// 渡す）。
  factory FfiEmulatorSession.create({
    required String homeDir,
    String? romDir,
    BootMode bootMode = BootMode.basic,
    BubiCoreBindings? bindings,
    int commandQueueCapacity = 0,
    int eventQueueCapacity = 0,
    Duration pollInterval = const Duration(milliseconds: 16),
    VideoTextureAttacher? textures,
    AudioSink? audio,
  }) {
    if (homeDir.isEmpty) {
      throw const EmulatorException(
        EmulatorErrorCode.invalidArgument,
        'homeDir を空にできません。',
      );
    }

    final resolved = bindings ?? BubiCoreBindings.open();
    final options = calloc<BfmCreateOptions>();
    final out = calloc<Pointer<BfmSession>>();
    final homeDirUtf8 = homeDir.toNativeUtf8();
    final romDirUtf8 = romDir == null || romDir.isEmpty
        ? null
        : romDir.toNativeUtf8();
    try {
      options.ref.homeDir = homeDirUtf8.cast<Char>();
      options.ref.romDir = romDirUtf8 == null
          ? nullptr
          : romDirUtf8.cast<Char>();
      options.ref.bootMode = bootModeToNative(bootMode);
      options.ref.commandQueueCapacity = commandQueueCapacity;
      options.ref.eventQueueCapacity = eventQueueCapacity;

      final result = resolved.create(options, out);
      if (result != BfmResult.ok) {
        final code = errorCodeFromNative(result);
        throw EmulatorException(code, describeErrorCode(code));
      }
      return FfiEmulatorSession._(
        resolved,
        out.value,
        pollInterval,
        textures,
        audio,
      );
    } finally {
      // C境界を跨いだメモリは確保側が解放する。パスはネイティブ側が
      // 複製するため、この時点で手放してよい。
      calloc.free(homeDirUtf8);
      if (romDirUtf8 != null) {
        calloc.free(romDirUtf8);
      }
      calloc.free(out);
      calloc.free(options);
    }
  }

  final BubiCoreBindings _bindings;
  final VideoTextureAttacher? _textures;
  int? _textureId;
  final Duration _pollInterval;
  final AudioSink? _audio;

  Pointer<BfmSession> _handle;
  Timer? _pollTimer;
  bool _disposed = false;

  // 音声。design.md 7「音声設計」。pull間隔はUIの描画周期に結合させない
  // （[_pollInterval] と同じ理由）。
  static const Duration _audioPullInterval = Duration(milliseconds: 20);
  Timer? _audioTimer;
  Pointer<Int16>? _audioScratch;
  int _audioScratchFrames = 0;
  int _audioChannels = 2;

  final StreamController<EmulatorEvent> _events =
      StreamController<EmulatorEvent>.broadcast();

  SessionState _lastKnownState = SessionState.stopped;

  /// 直近の状態。
  ///
  /// イベントキューは飽和時に古いものから捨てるため（design.md 16.1）、
  /// [LifecycleChanged] の受信だけで状態を組み立てると、取りこぼした
  /// 瞬間から永久にずれる。権威はネイティブ側のスナップショットに置く。
  @override
  SessionState get state {
    if (_disposed) {
      return _lastKnownState;
    }
    _lastKnownState = sessionStateFromNative(_bindings.getState(_handle));
    return _lastKnownState;
  }

  @override
  Stream<EmulatorEvent> get events => _events.stream;

  @override
  Future<void> start() async {
    _ensureUsable();
    final result = _bindings.start(_handle);
    if (result != BfmResult.ok) {
      final code = errorCodeFromNative(result);
      throw EmulatorException(code, describeErrorCode(code));
    }
    _lastKnownState = SessionState.starting;
    _pollTimer ??= Timer.periodic(_pollInterval, (_) => _drainEvents());
    await _startAudio();
  }

  @override
  Future<void> stop() async {
    if (_disposed) {
      return; // 破棄済みの停止は無害に済ませる
    }
    final result = _bindings.stop(_handle);
    if (result != BfmResult.ok) {
      final code = errorCodeFromNative(result);
      throw EmulatorException(code, describeErrorCode(code));
    }
    // 停止までに積まれたイベントを取りこぼさない。
    _drainEvents();
    _pollTimer?.cancel();
    _pollTimer = null;
    await _stopAudio();
  }

  /// [_audio] があれば`bfm_get_audio_format`で得たフォーマットで再生を始め、
  /// [_audioPullInterval] ごとに`bfm_read_audio`で引き出して供給する。
  /// 音声側からVMを進めることはない（design.md 16.1「音声はVMの駆動源に
  /// しない」）。この引き出しはメインisolateの`Timer`が行うだけで、
  /// 実時間制約のある音声ミキシングのコールバックそのものではない
  /// （そちらはSoLoudエンジン内部にあり、ここからは触れない）。
  Future<void> _startAudio() async {
    final audio = _audio;
    if (audio == null) {
      return;
    }
    final sampleRate = calloc<Uint32>();
    final channels = calloc<Uint32>();
    try {
      final result = _bindings.getAudioFormat(_handle, sampleRate, channels);
      if (result != BfmResult.ok) {
        return;
      }
      _audioChannels = channels.value;
      _audioScratchFrames =
          (sampleRate.value * _audioPullInterval.inMilliseconds / 1000).round();
      _audioScratch = calloc<Int16>(_audioScratchFrames * _audioChannels);
      await audio.start(sampleRate: sampleRate.value, channels: _audioChannels);
      _audioTimer ??= Timer.periodic(_audioPullInterval, (_) => _pullAudio());
    } finally {
      calloc.free(sampleRate);
      calloc.free(channels);
    }
  }

  void _pullAudio() {
    final scratch = _audioScratch;
    final audio = _audio;
    if (_disposed || scratch == null || audio == null) {
      return;
    }
    final result = _bindings.readAudio(_handle, scratch, _audioScratchFrames);
    if (result != BfmResult.ok) {
      return;
    }
    final byteLength = _audioScratchFrames * _audioChannels * 2;
    // ネイティブ領域そのままではなく複製を渡す。scratchは次のtickで
    // 上書きするため、非同期に処理されても壊れない値を渡す必要がある。
    final bytes = Uint8List.fromList(
      scratch.cast<Uint8>().asTypedList(byteLength),
    );
    audio.pushPcm16(bytes);
  }

  Future<void> _stopAudio() async {
    _audioTimer?.cancel();
    _audioTimer = null;
    final scratch = _audioScratch;
    _audioScratch = null;
    if (scratch != null) {
      calloc.free(scratch);
    }
    await _audio?.stop();
  }

  @override
  Future<int> reset(ResetKind kind) async {
    _ensureUsable();
    final out = calloc<Uint64>();
    try {
      final result = _bindings.reset(_handle, resetKindToNative(kind), out);
      if (result != BfmResult.ok) {
        final code = errorCodeFromNative(result);
        throw EmulatorException(code, describeErrorCode(code));
      }
      return out.value;
    } finally {
      calloc.free(out);
    }
  }

  @override
  Future<int> setBootMode(BootMode mode) async {
    _ensureUsable();
    final command = calloc<BfmCommand>();
    final out = calloc<Uint64>();
    try {
      command.ref.kind = BfmCommandKind.setBootMode;
      command.ref.arg0 = bootModeToNative(mode);
      final result = _bindings.sendCommand(_handle, command, out);
      if (result != BfmResult.ok) {
        final code = errorCodeFromNative(result);
        throw EmulatorException(code, describeErrorCode(code));
      }
      return out.value;
    } finally {
      calloc.free(out);
      calloc.free(command);
    }
  }

  @override
  Future<void> keyDown(int vkCode) =>
      _sendKeyCommand(BfmCommandKind.keyDown, vkCode);

  @override
  Future<void> keyUp(int vkCode) =>
      _sendKeyCommand(BfmCommandKind.keyUp, vkCode);

  Future<void> _sendKeyCommand(int kind, int vkCode) async {
    _ensureUsable();
    final command = calloc<BfmCommand>();
    final out = calloc<Uint64>();
    try {
      command.ref.kind = kind;
      command.ref.arg0 = vkCode;
      final result = _bindings.sendCommand(_handle, command, out);
      if (result != BfmResult.ok) {
        final code = errorCodeFromNative(result);
        throw EmulatorException(code, describeErrorCode(code));
      }
    } finally {
      calloc.free(out);
      calloc.free(command);
    }
  }

  /// コアが実際にROMを読み `USERDIC.DAT` を書くディレクトリ。
  ///
  /// 連結規則はupstreamが決めるため、Dart側で組み立てずここから得る。
  /// 診断表示に使う場合はフルパスをそのまま通常ログへ残さない（NFR-07）。
  String readCoreDirectory() {
    _ensureUsable();
    const capacity = 4096;
    final buffer = calloc<Uint8>(capacity);
    try {
      final result = _bindings.getCoreDirectory(
        _handle,
        buffer.cast<Char>(),
        capacity,
      );
      if (result != BfmResult.ok) {
        final code = errorCodeFromNative(result);
        throw EmulatorException(code, describeErrorCode(code));
      }
      return buffer.cast<Utf8>().toDartString();
    } finally {
      calloc.free(buffer);
    }
  }

  @override
  EmulatorStats readStats() {
    _ensureUsable();
    final out = calloc<BfmStats>();
    try {
      final result = _bindings.getStats(_handle, out);
      if (result != BfmResult.ok) {
        final code = errorCodeFromNative(result);
        throw EmulatorException(code, describeErrorCode(code));
      }
      return EmulatorStats(
        framesRun: out.ref.framesRun,
        commandsAccepted: out.ref.commandsAccepted,
        commandsRejected: out.ref.commandsRejected,
        eventsDropped: out.ref.eventsDropped,
        vmAccessViolations: out.ref.vmAccessViolations,
        framesPublished: out.ref.framesPublished,
        framesDropped: out.ref.framesDropped,
        audioFramesProduced: out.ref.audioFramesProduced,
        audioUnderrunFrames: out.ref.audioUnderrunFrames,
        audioOverrunFrames: out.ref.audioOverrunFrames,
      );
    } finally {
      calloc.free(out);
    }
  }

  @override
  Future<int> attachVideoTexture() async {
    _ensureUsable();
    final existing = _textureId;
    if (existing != null) {
      return existing;
    }
    final textures = _textures;
    if (textures == null) {
      throw const EmulatorException(
        EmulatorErrorCode.invalidState,
        'textures を渡さずに生成したセッションはTextureへ接続できません。',
      );
    }
    final id = await textures.attach(_handle.address);
    _textureId = id;
    return id;
  }

  @override
  Future<void> detachVideoTexture() async {
    final id = _textureId;
    if (id == null) {
      return; // 解除は冪等
    }
    _textureId = null;
    await _textures?.detach(id);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return; // 破棄は冪等
    }
    _disposed = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    // 終了順序: 入力停止 → コマンド受付停止 → コア停止 → Texture/音声解放 →
    // セッション破棄（design.md 5.1）。Texture を先に外さないと、
    // 描画スレッドが解放済みのセッションを読む。音声も同様に、
    // セッション破棄後は`bfm_read_audio`を呼べない。
    await detachVideoTexture();
    await _stopAudio();
    _bindings.destroy(_handle);
    _handle = nullptr;
    await _events.close();
  }

  /// コアが積んだイベントを空になるまで引き取る。
  ///
  /// 引き取れなかった分はネイティブ側で古いものから捨てられる。
  /// UIの遅れでコアを待たせない方針（design.md 16.1）に合わせる。
  void _drainEvents() {
    if (_disposed) {
      return;
    }
    final buffer = calloc<BfmEvent>();
    try {
      while (_bindings.pollEvent(_handle, buffer) == BfmResult.ok) {
        final event = emulatorEventFromNative(
          kind: buffer.ref.kind,
          code: buffer.ref.code,
          commandId: buffer.ref.commandId,
          arg0: buffer.ref.arg0,
          arg1: buffer.ref.arg1,
        );
        if (event is LifecycleChanged) {
          _lastKnownState = event.state;
        }
        if (!_events.isClosed) {
          _events.add(event);
        }
      }
    } finally {
      calloc.free(buffer);
    }
  }

  void _ensureUsable() {
    if (_disposed) {
      throw const EmulatorException(
        EmulatorErrorCode.invalidState,
        '破棄済みのセッションは操作できません。',
      );
    }
  }
}
