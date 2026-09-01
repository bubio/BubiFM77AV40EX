/// 1つのROMファイルの検証結果（design.md 10）。
enum RomStatus {
  /// ファイルが見つからない。
  missing,

  /// 見つかったが読めない。権限や媒体の異常。
  unreadable,

  /// サイズが仕様と違う。別機種のROMや破損の可能性がある。
  wrongSize,

  /// 承認済みmanifestのSHA-256と一致しない。破損または異版。
  hashMismatch,

  /// 名前、サイズ、SHA-256のすべてが一致した。
  verified,

  /// 名前とサイズは一致したが、照合するmanifestがない。
  sizeOnly,
}

extension RomStatusX on RomStatus {
  /// この状態のROMをコアへ渡してよいか。
  ///
  /// manifest未提供を起動失敗にしない（specification.md 6）。
  bool get isUsable => this == RomStatus.verified || this == RomStatus.sizeOnly;

  /// 利用者へ原因として提示すべきか。
  bool get isProblem => !isUsable;
}
