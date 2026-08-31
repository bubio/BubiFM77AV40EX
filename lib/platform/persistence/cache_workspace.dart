/// 破棄可能な作業領域。
///
/// design.md 11.2 の`CacheWorkspace`境界。FDDの変換結果、
/// content URI媒体のセッション展開、録画途中データを置く。
/// 消失しても永続データを失わず再構築できることを前提にする。
abstract interface class CacheWorkspace {
  /// セッション専用の作業ディレクトリを確保する。
  Future<WorkspaceHandle> createSessionWorkspace();

  /// 起動時に残存する放棄済みワークスペースを削除する。
  Future<void> purgeAbandonedWorkspaces();
}

abstract interface class WorkspaceHandle {
  String get nativePath;

  /// 作業領域内へ原本を複製し、複製先のOSパスを返す。
  Future<String> importCopy(
    String sourceNativePath, {
    required String fileName,
  });

  /// 作業領域内のファイルを列挙する。
  Future<List<String>> listFiles();

  Future<void> dispose();
}
