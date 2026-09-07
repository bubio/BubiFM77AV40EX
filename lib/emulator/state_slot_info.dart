import 'dart:typed_data';

/// 状態スロット（0〜9）の一覧表示用情報（STA-01）。
///
/// `metadata.json`の存在をスロットが有効かどうかの判定基準にする
/// （design.md「状態保存（M3、STA-01/STA-02）の実装方式」）。
class StateSlotInfo {
  const StateSlotInfo({
    required this.slot,
    required this.hasData,
    this.savedAt,
    this.diskNames = const [],
    this.thumbnailBytes,
  });

  final int slot;

  /// `metadata.json`が存在し読めたかどうか。
  final bool hasData;

  /// 保存日時。[hasData]がfalseならnull。
  final DateTime? savedAt;

  /// 保存時点でFD1/FD2に挿入されていた媒体の表示名（空でないものだけ）。
  final List<String> diskNames;

  /// 保存時点の画面のサムネイル（PNGバイト列）。保存されていなければnull。
  final Uint8List? thumbnailBytes;
}
