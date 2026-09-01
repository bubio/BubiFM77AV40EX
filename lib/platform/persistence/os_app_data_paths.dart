import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_data_paths.dart';

/// OS標準の保存領域を使う [AppDataPaths]（design.md 11.2、11.3）。
///
/// macOSは`~/Library/Application Support/BubiFM77AV40EX/`。
/// 物理パスの組み立てはここだけで行い、feature層へ露出させない。
class OsAppDataPaths implements AppDataPaths {
  OsAppDataPaths({this.applicationName = 'BubiFM77AV40EX'});

  final String applicationName;
  Directory? _root;

  /// アプリケーションデータの基準ディレクトリ。
  ///
  /// design.md 11.3 は macOS で `~/Library/Application Support/
  /// BubiFM77AV40EX/` と定める。利用者が自分でROMを置くフォルダーが
  /// この下にあるため、位置は案内できる名前で固定する。
  ///
  /// `path_provider` はバンドル識別子ごとの位置を返すため、その親
  /// （OS APIが返すApplication Supportそのもの）へアプリ名を足す。
  /// 基準の取得はOS APIに任せ、末尾の名前だけを仕様に合わせる。
  /// コアの作業ディレクトリもこの下に置く（design.md 16.1）。
  Future<Directory> root() async {
    final cached = _root;
    if (cached != null) {
      return cached;
    }
    final support = await getApplicationSupportDirectory();
    final directory = Directory('${support.parent.path}/$applicationName');
    await directory.create(recursive: true);
    return _root = directory;
  }

  /// 利用者がROMを置くフォルダー（`roms/`）。
  ///
  /// アプリは選ばせず、この位置に固定する（specification.md 6）。
  /// 見つけてもらう必要があるため、存在しなければ作る。
  Future<Directory> romsDirectory() async {
    final base = await root();
    final directory = Directory('${base.path}/roms');
    await directory.create(recursive: true);
    return directory;
  }

  /// 一時作業領域（`~/Library/Caches/BubiFM77AV40EX/`）。
  ///
  /// 消えてよいデータだけを置く（design.md 11.3）。
  Future<Directory> cacheRoot() async {
    final cache = await getApplicationCacheDirectory();
    final directory = Directory('${cache.parent.path}/$applicationName');
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<String> romsDirectoryPath() async => (await romsDirectory()).path;

  @override
  Future<AppDataLocation> stateSlot(int slotIndex) =>
      _location('states/slot-$slotIndex');

  @override
  Future<AppDataLocation> dictionaryUserData() =>
      _location('dictionary/USERDIC.DAT');

  @override
  Future<AppDataLocation> keymaps() => _location('keymaps');

  @override
  Future<AppDataLocation> history() => _location('history.json');

  Future<AppDataLocation> _location(String relativePath) async {
    final base = await root();
    return _FileAppDataLocation(File('${base.path}/$relativePath'));
  }
}

class _FileAppDataLocation implements AppDataLocation {
  _FileAppDataLocation(this._file);

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
    // 同一ディレクトリの一時ファイルへ書いてから置換する。
    // 別ディレクトリだと rename が別ボリューム跨ぎになりうる。
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsBytes(bytes, flush: true);
    await temporary.rename(_file.path);
  }

  @override
  Future<void> delete() async {
    if (await _file.exists()) {
      await _file.delete();
    }
  }
}
