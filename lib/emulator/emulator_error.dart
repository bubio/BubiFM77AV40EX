/// コア境界が返すエラー分類。ネイティブ側の `bfm_result` に対応する。
enum EmulatorErrorCode {
  /// 呼び出し側の誤り（NULL、範囲外など）。
  invalidArgument,

  /// その状態では実行できない操作（二重起動、停止中のコマンドなど）。
  invalidState,

  /// コマンドキューが上限に達した。利用者操作は黙って捨てず、ここで拒否する。
  queueFull,

  /// 取り出せるイベントがない。
  noEvent,

  /// Core thread 内で異常が発生した。
  coreFailed,

  /// 型としては定義済みだが、まだ実装していないコマンド種別。
  unsupported,

  /// 境界で捕捉した想定外の例外。
  internal,

  /// rawイメージのサイズがFM7系の2D/2DDジオメトリのどちらとも一致しない、
  /// または変換形式の変換後media_typeが2D/2DD以外だった（FDD-03）。
  unsupportedGeometry,

  /// 状態読込み対象ファイルの先頭バージョンが既知値と一致しない、または
  /// 読めない（STA-02）。コア内部でさらに深い不一致がある場合はこの
  /// コードでは表せない（design.md「状態保存（M3、STA-01/STA-02）の
  /// 実装方式」参照）。
  stateIncompatible,

  /// 既知のどれにも当てはまらない値。ヘッダーとの同期漏れを表す。
  unknown,
}

/// コア境界の呼び出しが失敗したことを表す例外。
class EmulatorException implements Exception {
  const EmulatorException(this.code, this.message);

  final EmulatorErrorCode code;
  final String message;

  @override
  String toString() => 'EmulatorException(${code.name}): $message';
}
