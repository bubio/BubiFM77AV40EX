import 'rom_probe.dart';

/// ROMディレクトリを走査して実測値を集める境界。
///
/// 実装は`platform`にあり、`features`はこの抽象だけを使う。
/// ROM本体のバイト列を返さないことで、design.md 10 の
/// 「ROM本体をDartヒープへ載せない」を型で守る。
abstract interface class RomScanner {
  /// [directoryPath] 直下の [fileNames] を調べる。
  ///
  /// 存在しないファイルは結果に含めない。呼び出し側は
  /// `RomInventory.evaluate` で欠落として扱う。
  ///
  /// [computeHashes] が真のときだけSHA-256を計算する。承認済みmanifestが
  /// ない場合は計算しない。計算はUIスレッドを止めない場所で行う。
  Future<List<RomProbe>> scan({
    required String directoryPath,
    required Set<String> fileNames,
    bool computeHashes = false,
  });
}
