import 'package:bubi_fm77av40ex/emulator/rom/rom_probe.dart';
import 'package:bubi_fm77av40ex/emulator/rom/rom_scanner.dart';
import 'package:bubi_fm77av40ex/platform/persistence/app_data_paths.dart';
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
  FakeAppDataPaths({this.romsPath = '/data/BubiFM77AV40EX/roms'});

  String romsPath;

  /// 位置の解決そのものが失敗する場合に投げる例外。
  Object? throwOnRomsPath;

  int romsPathCallCount = 0;

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
  Future<AppDataLocation> stateSlot(int slotIndex) =>
      throw UnimplementedError();

  @override
  Future<AppDataLocation> dictionaryUserData() => throw UnimplementedError();

  @override
  Future<AppDataLocation> keymaps() => throw UnimplementedError();

  @override
  Future<AppDataLocation> history() => throw UnimplementedError();
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
