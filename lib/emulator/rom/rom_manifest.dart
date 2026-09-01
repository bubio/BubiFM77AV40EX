/// 利用者が正規ROMから承認したSHA-256の一覧（specification.md 6）。
///
/// ROM本体は含まず、ファイル名・サイズ・SHA-256だけを持つ。版管理してよい
/// データであり、リポジトリへROMを持ち込まずに検証を強められる。
/// manifestがない版は`sizeOnly`として起動を許可する。
class RomManifest {
  const RomManifest(this._entriesByFileName);

  /// ファイル名（大文字小文字を区別しない）からエントリーを引く。
  factory RomManifest.fromEntries(Iterable<RomManifestEntry> entries) {
    return RomManifest({
      for (final entry in entries) entry.fileName.toUpperCase(): entry,
    });
  }

  /// JSONから読む。想定しない形なら [FormatException] を投げる。
  ///
  /// ```json
  /// {"version": 1, "roms": [
  ///   {"fileName": "INITIATE.ROM", "sizeInBytes": 8192, "sha256": "…"}
  /// ]}
  /// ```
  factory RomManifest.fromJson(Map<String, Object?> json) {
    final roms = json['roms'];
    if (roms is! List) {
      throw const FormatException('manifest に roms の配列がありません。');
    }
    return RomManifest.fromEntries(
      roms.map((entry) {
        if (entry is! Map<String, Object?>) {
          throw const FormatException('roms の要素がオブジェクトではありません。');
        }
        final fileName = entry['fileName'];
        final sizeInBytes = entry['sizeInBytes'];
        final sha256 = entry['sha256'];
        if (fileName is! String || sizeInBytes is! int || sha256 is! String) {
          throw const FormatException('roms の要素に必要な項目がありません。');
        }
        return RomManifestEntry(
          fileName: fileName,
          sizeInBytes: sizeInBytes,
          sha256: sha256.toLowerCase(),
        );
      }),
    );
  }

  final Map<String, RomManifestEntry> _entriesByFileName;

  bool get isEmpty => _entriesByFileName.isEmpty;

  RomManifestEntry? entryFor(String fileName) =>
      _entriesByFileName[fileName.toUpperCase()];
}

/// manifestの1件。ROMバイト列は保持しない。
class RomManifestEntry {
  const RomManifestEntry({
    required this.fileName,
    required this.sizeInBytes,
    required this.sha256,
  });

  final String fileName;
  final int sizeInBytes;

  /// 小文字16進のSHA-256。
  final String sha256;
}
