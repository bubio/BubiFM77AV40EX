import 'dart:io';
import 'dart:math';

import 'cache_workspace.dart';
import 'os_app_data_paths.dart';

/// OS標準のキャッシュ領域を使う [CacheWorkspace]（design.md 11.2、16.1）。
///
/// `~/Library/Caches/BubiFM77AV40EX/fdd-sessions/<id>/` にセッションごとの
/// 作業ディレクトリを作る。FDDの原本はここへ複製してからコアへ渡し
/// （design.md 9.1「原子的に書き戻し」、16.1）、排出後は
/// [WorkspaceHandle.exportAtomic] で原本のディレクトリへ同一ボリュームの
/// rename により反映する。
class OsCacheWorkspace implements CacheWorkspace {
  OsCacheWorkspace({OsAppDataPaths? appDataPaths})
    : _appDataPaths = appDataPaths ?? OsAppDataPaths();

  static const _sessionsDirName = 'fdd-sessions';

  final OsAppDataPaths _appDataPaths;
  final Random _random = Random.secure();

  Future<Directory> _sessionsRoot() async {
    final cache = await _appDataPaths.cacheRoot();
    final directory = Directory('${cache.path}/$_sessionsDirName');
    await directory.create(recursive: true);
    return directory;
  }

  @override
  Future<WorkspaceHandle> createSessionWorkspace() async {
    final root = await _sessionsRoot();
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
    final directory = Directory('${root.path}/$id');
    await directory.create(recursive: true);
    return _OsWorkspaceHandle(directory);
  }

  @override
  Future<void> purgeAbandonedWorkspaces() async {
    final root = await _sessionsRoot();
    await for (final entry in root.list()) {
      await entry.delete(recursive: true);
    }
  }
}

class _OsWorkspaceHandle implements WorkspaceHandle {
  _OsWorkspaceHandle(this._directory);

  final Directory _directory;

  @override
  String get nativePath => _directory.path;

  @override
  Future<String> importCopy(
    String sourceNativePath, {
    required String fileName,
  }) async {
    final destination = File('${_directory.path}/$fileName');
    await File(sourceNativePath).copy(destination.path);
    return destination.path;
  }

  /// 作業領域内の [workspaceFileName] を、原本 [destinationNativePath] と
  /// 同じディレクトリの一時ファイルへコピーしてから rename で置換する
  /// （design.md 16.1）。原本のディレクトリと作業領域は別ボリューム
  /// にありうるため、一時ファイルは原本側のディレクトリへ作る。
  @override
  Future<void> exportAtomic(
    String workspaceFileName,
    String destinationNativePath,
  ) async {
    final source = File('${_directory.path}/$workspaceFileName');
    final destination = File(destinationNativePath);
    final temporary = File('${destination.path}.tmp');
    await source.copy(temporary.path);
    try {
      await temporary.rename(destination.path);
    } on FileSystemException {
      // 一時ファイルはすでに原本側のディレクトリにあるため、この経路は
      // 通常は起きない。何らかの理由でrenameが使えない場合の保険として、
      // コピーしてから一時ファイルを消す。
      await temporary.copy(destination.path);
      await temporary.delete();
    }
  }

  @override
  Future<List<String>> listFiles() async {
    final entries = await _directory.list().toList();
    return [
      for (final entry in entries)
        if (entry is File) entry.path,
    ];
  }

  @override
  Future<void> dispose() async {
    if (await _directory.exists()) {
      await _directory.delete(recursive: true);
    }
  }
}
