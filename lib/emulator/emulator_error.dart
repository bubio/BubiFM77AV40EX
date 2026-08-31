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
