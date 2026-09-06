import 'dart:async';
import 'dart:io';

import 'package:bubi_fm77av40ex/emulator/emulator_error.dart';
import 'package:bubi_fm77av40ex/emulator/emulator_event.dart';
import 'package:bubi_fm77av40ex/emulator/emulator_session.dart';
import 'package:bubi_fm77av40ex/emulator/emulator_stats.dart';
import 'package:bubi_fm77av40ex/emulator/rom/rom_probe.dart';
import 'package:bubi_fm77av40ex/emulator/rom/rom_scanner.dart';
import 'package:bubi_fm77av40ex/emulator/session_state.dart';
import 'package:bubi_fm77av40ex/platform/persistence/app_data_paths.dart';
import 'package:bubi_fm77av40ex/platform/persistence/cache_workspace.dart';
import 'package:bubi_fm77av40ex/platform/persistence/external_file_access.dart';
import 'package:bubi_fm77av40ex/platform/persistence/preferences_store.dart';

const int kib = 1024;

/// 起動必須6ファイルの正常な実測値。
List<RomProbe> bootRequiredProbes() => [
  RomProbe(fileName: 'INITIATE.ROM', sizeInBytes: 8 * kib, readable: true),
  RomProbe(fileName: 'SUBSYS_A.ROM', sizeInBytes: 8 * kib, readable: true),
  RomProbe(fileName: 'SUBSYS_B.ROM', sizeInBytes: 8 * kib, readable: true),
  RomProbe(fileName: 'SUBSYS_C.ROM', sizeInBytes: 10 * kib, readable: true),
  RomProbe(fileName: 'SUBSYSCG.ROM', sizeInBytes: 8 * kib, readable: true),
  RomProbe(fileName: 'EXTSUB.ROM', sizeInBytes: 48 * kib, readable: true),
];

class FakePreferencesStore implements PreferencesStore {
  final Map<String, Object> values = {};

  @override
  String? getString(String key) => values[key] as String?;

  @override
  int? getInt(String key) => values[key] as int?;

  @override
  double? getDouble(String key) => values[key] as double?;

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  Future<void> setString(String key, String value) async => values[key] = value;

  @override
  Future<void> setInt(String key, int value) async => values[key] = value;

  @override
  Future<void> setDouble(String key, double value) async => values[key] = value;

  @override
  Future<void> setBool(String key, bool value) async => values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);

  @override
  Future<void> flush() async {}
}

/// ROMフォルダーの位置を返すだけの`AppDataPaths`。
///
/// 物理パスは実装が決めるため、featureの試験では固定値でよい。
class FakeAppDataPaths implements AppDataPaths {
  FakeAppDataPaths({
    this.romsPath = '/data/BubiFM77AV40EX/roms',
    this.homePath = '/data/BubiFM77AV40EX',
  });

  String romsPath;
  String homePath;
  String? picturesPath = '/data/BubiFM77AV40EX/pictures';

  /// 位置の解決そのものが失敗する場合に投げる例外。
  Object? throwOnRomsPath;

  int romsPathCallCount = 0;

  @override
  Future<String> coreHomeDirectoryPath() async => homePath;

  @override
  Future<String> romsDirectoryPath() async {
    romsPathCallCount++;
    final failure = throwOnRomsPath;
    if (failure != null) {
      throw failure;
    }
    return romsPath;
  }

  @override
  Future<AppDataLocation?> pictureFile(String fileName) async {
    final base = picturesPath;
    if (base == null) {
      return null;
    }
    return FakeFileAppDataLocation(File('$base/$fileName'));
  }

  @override
  Future<AppDataLocation> stateSlot(int slotIndex) =>
      throw UnimplementedError();

  @override
  Future<AppDataLocation> dictionaryUserData() => throw UnimplementedError();

  @override
  Future<AppDataLocation> keymaps() => throw UnimplementedError();

  @override
  Future<AppDataLocation> history() => throw UnimplementedError();
}

/// 実ファイルへ書く[AppDataLocation]のテスト用実装。
///
/// テストコードは`dart:io`へ触れてよい（架構テストが禁じるのは
/// `lib/features`だけ）ため、実際に書き出されたか検証できるようにする。
class FakeFileAppDataLocation implements AppDataLocation {
  FakeFileAppDataLocation(this._file);

  final File _file;

  @override
  String get nativePath => _file.path;

  @override
  Future<bool> exists() => _file.exists();

  @override
  Future<List<int>> read() => _file.readAsBytes();

  @override
  Future<void> writeAtomic(List<int> bytes) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> delete() async {
    if (await _file.exists()) {
      await _file.delete();
    }
  }
}

class FakeRomScanner implements RomScanner {
  List<RomProbe> result = const [];

  /// 走査そのものが失敗する場合に投げる例外。
  Object? throwOnScan;

  String? lastDirectoryPath;
  Set<String>? lastFileNames;
  bool? lastComputeHashes;

  @override
  Future<List<RomProbe>> scan({
    required String directoryPath,
    required Set<String> fileNames,
    bool computeHashes = false,
  }) async {
    lastDirectoryPath = directoryPath;
    lastFileNames = fileNames;
    lastComputeHashes = computeHashes;
    final failure = throwOnScan;
    if (failure != null) {
      throw failure;
    }
    return result;
  }
}

/// `EmulatorController`のFDD試験向けの最小限の`EmulatorSession`。
///
/// 起動やキー入力など本試験で使わない経路は`UnimplementedError`のまま
/// にする。呼ばれたら試験の前提が崩れているという合図にする。
class FakeEmulatorSession implements EmulatorSession {
  final _events = StreamController<EmulatorEvent>.broadcast();
  int _nextCommandId = 1;

  final List<(int drive, String imagePath, int bank)> insertCalls = [];
  final List<int> ejectCalls = [];
  final List<ResetKind> resetCalls = [];
  final List<BootMode> setBootModeCalls = [];
  final List<int> setSpeedMultiplierCalls = [];
  final List<bool> setFullSpeedCalls = [];
  final List<CpuType> setCpuTypeCalls = [];
  final List<RunOptionSwitches> setRunOptionSwitchesCalls = [];
  final List<(int drive, bool enabled)> setFddWriteProtectCalls = [];
  final List<(int drive, bool enabled)> setFddTimingCalls = [];
  final List<(int drive, bool ignore)> setFddCrcCheckCalls = [];
  final List<(FddMediaType mediaType, String destinationPath)>
  createBlankFddCalls = [];

  /// [getFddBankInfo]が返す値。キーはドライブ番号。未登録なら未挿入
  /// （bankNum=0、curBank=0）を返す。
  final Map<int, ({int bankNum, int curBank})> fddBankInfoByDrive = {};

  /// [getFddWriteProtect]が返す値。キーはドライブ番号。未登録なら
  /// false。ネイティブ側と同様、[setFddWriteProtect]で更新され、
  /// [ejectFdd]の成功時にfalseへ戻る（マウント中の媒体自身が持つ状態、
  /// ドライブの記憶ではないことをFakeでも再現する）。
  final Map<int, bool> fddWriteProtectByDrive = {};

  /// 次に受理する挿入・排出コマンドの完了結果。nullなら成功。
  ///
  /// 使ったら消費して次回はnullへ戻る。コマンド完了は
  /// `EmulatorController`が`CommandCompleted`を待つため、呼ぶたびに
  /// マイクロタスクで自動的に出す。
  EmulatorErrorCode? nextInsertError;
  EmulatorErrorCode? nextEjectError;

  @override
  SessionState state = SessionState.running;

  @override
  Stream<EmulatorEvent> get events => _events.stream;

  void emit(EmulatorEvent event) => _events.add(event);

  @override
  Future<int> insertFdd(int drive, String imagePath, {int bank = 0}) async {
    insertCalls.add((drive, imagePath, bank));
    final id = _nextCommandId++;
    final error = nextInsertError;
    nextInsertError = null;
    scheduleMicrotask(() => emit(CommandCompleted(id, error: error)));
    return id;
  }

  @override
  Future<int> ejectFdd(int drive) async {
    ejectCalls.add(drive);
    fddWriteProtectByDrive[drive] = false;
    final id = _nextCommandId++;
    final error = nextEjectError;
    nextEjectError = null;
    scheduleMicrotask(() => emit(CommandCompleted(id, error: error)));
    return id;
  }

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<int> reset(ResetKind kind) async {
    resetCalls.add(kind);
    return _nextCommandId++;
  }

  @override
  Future<int> setBootMode(BootMode mode) async {
    setBootModeCalls.add(mode);
    return _nextCommandId++;
  }

  @override
  Future<int> setSpeedMultiplier(int multiplier) async {
    setSpeedMultiplierCalls.add(multiplier);
    return _nextCommandId++;
  }

  @override
  Future<int> setFullSpeed(bool enabled) async {
    setFullSpeedCalls.add(enabled);
    return _nextCommandId++;
  }

  @override
  Future<int> setCpuType(CpuType type) async {
    setCpuTypeCalls.add(type);
    return _nextCommandId++;
  }

  @override
  Future<int> setRunOptionSwitches(RunOptionSwitches switches) async {
    setRunOptionSwitchesCalls.add(switches);
    return _nextCommandId++;
  }

  @override
  Future<int> setFddWriteProtect(int drive, bool enabled) async {
    setFddWriteProtectCalls.add((drive, enabled));
    fddWriteProtectByDrive[drive] = enabled;
    return _nextCommandId++;
  }

  @override
  Future<int> setFddTiming(int drive, bool enabled) async {
    setFddTimingCalls.add((drive, enabled));
    return _nextCommandId++;
  }

  @override
  Future<int> setFddCrcCheck(int drive, bool ignore) async {
    setFddCrcCheckCalls.add((drive, ignore));
    return _nextCommandId++;
  }

  /// 次に受理する`createBlankFdd`の完了結果。nullなら成功。
  EmulatorErrorCode? nextCreateBlankFddError;

  @override
  Future<int> createBlankFdd(
    FddMediaType mediaType,
    String destinationPath,
  ) async {
    createBlankFddCalls.add((mediaType, destinationPath));
    final id = _nextCommandId++;
    final error = nextCreateBlankFddError;
    nextCreateBlankFddError = null;
    scheduleMicrotask(() => emit(CommandCompleted(id, error: error)));
    return id;
  }

  @override
  ({int bankNum, int curBank}) getFddBankInfo(int drive) =>
      fddBankInfoByDrive[drive] ?? (bankNum: 0, curBank: 0);

  @override
  bool getFddWriteProtect(int drive) => fddWriteProtectByDrive[drive] ?? false;

  @override
  Future<void> keyDown(int vkCode) async {}

  @override
  Future<void> keyUp(int vkCode) async {}

  /// `readStats()`が返す値。試験が差し替えて時間経過を模す。
  EmulatorStats stats = const EmulatorStats(
    framesRun: 0,
    commandsAccepted: 0,
    commandsRejected: 0,
    eventsDropped: 0,
    vmAccessViolations: 0,
    framesPublished: 0,
    framesDropped: 0,
    audioFramesProduced: 0,
    audioUnderrunFrames: 0,
    audioOverrunFrames: 0,
  );

  @override
  EmulatorStats readStats() => stats;

  double? lastVolume;

  @override
  void setVolume(double volume) {
    lastVolume = volume;
  }

  @override
  Future<int> attachVideoTexture() async => 0;

  @override
  Future<void> detachVideoTexture() async {}

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

/// 差し替え済みの結果を返すだけの`ExternalResource`。
class FakeExternalResource implements ExternalResource {
  FakeExternalResource(this.token, {String? displayName})
    : displayName = displayName ?? token;

  @override
  final String token;

  @override
  final String displayName;

  int releaseCallCount = 0;
  int withAccessCallCount = 0;

  @override
  Future<T> withAccess<T>(Future<T> Function(String nativePath) body) {
    withAccessCallCount++;
    return body(token);
  }

  @override
  Future<void> release() async {
    releaseCallCount++;
  }
}

/// あらかじめ用意した`ExternalResource`を1回だけ返す`ExternalFileAccess`。
class FakeExternalFileAccess implements ExternalFileAccess {
  ExternalResource? nextPickResult;
  ExternalResource? nextSaveLocationResult;

  /// [resolve]がトークンごとに返す結果。未登録ならnull（失効扱い）。
  final Map<String, ExternalResource?> resolveResultByToken = {};

  final List<String> resolveCalls = [];
  final List<String?> pickSaveLocationSuggestedNames = [];

  @override
  Future<ExternalResource?> pickDirectory({String? dialogTitle}) =>
      throw UnimplementedError();

  @override
  Future<ExternalResource?> pickFile({
    String? dialogTitle,
    List<String> allowedExtensions = const [],
  }) async {
    final result = nextPickResult;
    nextPickResult = null;
    return result;
  }

  @override
  Future<ExternalResource?> pickSaveLocation({
    String? dialogTitle,
    String? suggestedFileName,
  }) async {
    pickSaveLocationSuggestedNames.add(suggestedFileName);
    final result = nextSaveLocationResult;
    nextSaveLocationResult = null;
    return result;
  }

  @override
  Future<ExternalResource?> resolve(String token) async {
    resolveCalls.add(token);
    return resolveResultByToken[token];
  }
}

/// メモリ上に作業ディレクトリの操作記録だけを持つ`WorkspaceHandle`。
class FakeWorkspaceHandle implements WorkspaceHandle {
  final List<String> importedFileNames = [];
  final List<(String workspaceFileName, String destinationNativePath)>
  exportCalls = [];
  bool disposed = false;

  @override
  String get nativePath => '/cache/fdd-sessions/fake';

  @override
  Future<String> importCopy(
    String sourceNativePath, {
    required String fileName,
  }) async {
    importedFileNames.add(fileName);
    return '$nativePath/$fileName';
  }

  @override
  Future<void> exportAtomic(
    String workspaceFileName,
    String destinationNativePath,
  ) async {
    exportCalls.add((workspaceFileName, destinationNativePath));
  }

  @override
  Future<List<String>> listFiles() async => importedFileNames;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// 常に同じ[FakeWorkspaceHandle]を返す`CacheWorkspace`。
class FakeCacheWorkspace implements CacheWorkspace {
  final FakeWorkspaceHandle handle = FakeWorkspaceHandle();
  int createSessionWorkspaceCallCount = 0;
  int purgeAbandonedWorkspacesCallCount = 0;

  @override
  Future<WorkspaceHandle> createSessionWorkspace() async {
    createSessionWorkspaceCallCount++;
    return handle;
  }

  @override
  Future<void> purgeAbandonedWorkspaces() async {
    purgeAbandonedWorkspacesCallCount++;
  }
}
