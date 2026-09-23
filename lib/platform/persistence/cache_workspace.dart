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

  /// 作業領域内の [workspaceFileName] を [destinationNativePath] へ
  /// 原子的に書き戻す（design.md 9.1「原子的に書き戻し」、16.1）。
  ///
  /// 呼び出し側は、コアが書き込みを終えたことを確認してから呼ぶこと
  /// （FDDでは排出コマンドの完了を待つ）。
  Future<void> exportAtomic(
    String workspaceFileName,
    String destinationNativePath,
  );

  /// 作業領域内の [workspaceFileName] と [nativePath] の中身が同じか。
  /// 書き戻しを変更があったときだけに絞るために使う。
  Future<bool> contentEquals(String workspaceFileName, String nativePath);

  /// 作業領域内に [workspaceFileName] があるかどうか。
  Future<bool> exists(String workspaceFileName);

  /// 作業領域内の [workspaceFileName] を消す。無ければ何もしない。
  Future<void> delete(String workspaceFileName);

  /// 作業領域内のファイルを列挙する。
  Future<List<String>> listFiles();

  Future<void> dispose();
}
