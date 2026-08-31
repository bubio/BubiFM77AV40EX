/// 利用者が選んだ外部ファイル・フォルダーへの参照権。
///
/// design.md 11.2 の`ExternalFileAccess`境界。macOS/iOSの
/// security-scoped bookmark、AndroidのSAF persistable URI権限、
/// デスクトップの正規化パスをここへ閉じ込める。
abstract interface class ExternalFileAccess {
  /// フォルダーを選択させ、永続アクセス権を確保する。
  Future<ExternalResource?> pickDirectory({String? dialogTitle});

  /// ファイルを選択させ、永続アクセス権を確保する。
  Future<ExternalResource?> pickFile({
    String? dialogTitle,
    List<String> allowedExtensions = const [],
  });

  /// 保存先を選択させる。空ディスク、D88保存、録音出力で使用する。
  Future<ExternalResource?> pickSaveLocation({
    String? dialogTitle,
    String? suggestedFileName,
  });

  /// 保存済みトークンからアクセス権を復元する。失効時はnullを返す。
  Future<ExternalResource?> resolve(String token);
}

/// アクセス権を伴う外部リソース。
abstract interface class ExternalResource {
  /// 再取得のために永続化するトークン。パスそのものとは限らない。
  String get token;

  /// 表示用の名前。フルパスは通常ログへ残さない。
  String get displayName;

  /// アクセス権を開始してからコアへ渡すOSパスを得る。
  Future<T> withAccess<T>(Future<T> Function(String nativePath) body);

  /// アクセス権を解放する。
  Future<void> release();
}
