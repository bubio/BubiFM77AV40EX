/// ROMディレクトリから読み取った1ファイルの実測値。
///
/// 走査そのものは`platform`が行う。この型を挟むことで、検証規則を
/// ファイルシステムなしで試験できる。ROM本体のバイト列は保持しない。
class RomProbe {
  const RomProbe({
    required this.fileName,
    required this.sizeInBytes,
    required this.readable,
    this.sha256,
  });

  /// 読めなかったファイル。サイズは分からないこともある。
  const RomProbe.unreadable(this.fileName, {this.sizeInBytes})
    : readable = false,
      sha256 = null;

  final String fileName;

  /// 実サイズ。読めなかった場合はnullのことがある。
  final int? sizeInBytes;

  final bool readable;

  /// 小文字16進のSHA-256。manifestがない場合は計算しないためnull。
  final String? sha256;
}
