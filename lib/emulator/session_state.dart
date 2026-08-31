/// エミュレーターセッションのライフサイクル状態。
///
/// ネイティブ側の `bfm_state` と一対一に対応する。
enum SessionState {
  /// 未起動、または停止済み。
  stopped,

  /// 起動要求を受理し、Core thread の初期化を待っている。
  starting,

  /// Core thread が VM を実行している。
  running,

  /// 停止処理中。
  stopping,

  /// 初期化または実行中に異常が起きた。再開するには作り直す。
  failed,
}

/// リセットの種別（specification.md SYS-02）。
enum ResetKind {
  /// 通常リセット。
  normal,

  /// BREAK付き特殊リセット。
  special,
}
