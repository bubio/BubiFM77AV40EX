/// アプリケーションデータ領域の論理的な位置。
///
/// design.md 11.2/11.3 の`AppDataPaths`境界。実際の物理パスは
/// プラットフォームアダプターがOS APIから取得する。feature層は
/// ここで得た識別子だけを扱い、パス文字列を組み立てない。
abstract interface class AppDataPaths {
  /// 状態スロット（`states/slot-N/`）を表すハンドル。
  Future<AppDataLocation> stateSlot(int slotIndex);

  /// 辞書学習データ（`dictionary/USERDIC.DAT`）。
  Future<AppDataLocation> dictionaryUserData();

  /// キーマップ定義（`keymaps/`）。
  Future<AppDataLocation> keymaps();

  /// 履歴（`history.json`）。
  Future<AppDataLocation> history();
}

/// 永続データの位置と原子的な書込み手段。
abstract interface class AppDataLocation {
  /// コアへ渡すためのOSパス。ログへ出す場合は短縮する。
  String get nativePath;

  Future<bool> exists();

  Future<List<int>> read();

  /// 同一ディレクトリの一時ファイルへ書いてから原子的に置換する。
  Future<void> writeAtomic(List<int> bytes);

  Future<void> delete();
}
