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

/// ブートモード（specification.md SYS-04）。
///
/// 変更はコアが次のリセットで読むため、選択しただけでは切り替わらない。
enum BootMode {
  /// F-BASIC V3.0 で起動する。F-BASIC ROM が必要。
  basic,

  /// DOSで起動する。F-BASIC ROM がなくても起動できる。
  dos,
}

/// CPU種別（specification.md SYS-05）。
///
/// コアの`update_config()`が読み直すため、選択すると即座に切り替わる。
enum CpuType {
  /// 2.0MHz相当。
  fast,

  /// 1.2MHz。
  slow,
}

/// 実行設定のトグル項目（specification.md SYS-06）。
///
/// [cycleSteal]と[syncToHsync]は即時反映される。[extendedRam]はコアが
/// リセット時にしか読まないため、次のリセットまで見た目に反映されない。
class RunOptionSwitches {
  const RunOptionSwitches({
    this.cycleSteal = false,
    this.extendedRam = false,
    this.syncToHsync = false,
  });

  final bool cycleSteal;
  final bool extendedRam;
  final bool syncToHsync;

  RunOptionSwitches copyWith({
    bool? cycleSteal,
    bool? extendedRam,
    bool? syncToHsync,
  }) {
    return RunOptionSwitches(
      cycleSteal: cycleSteal ?? this.cycleSteal,
      extendedRam: extendedRam ?? this.extendedRam,
      syncToHsync: syncToHsync ?? this.syncToHsync,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RunOptionSwitches &&
      other.cycleSteal == cycleSteal &&
      other.extendedRam == extendedRam &&
      other.syncToHsync == syncToHsync;

  @override
  int get hashCode => Object.hash(cycleSteal, extendedRam, syncToHsync);
}

/// CPU速度倍率（specification.md SYS-03）。指数0=x1〜4=x16。
/// 「無制限」（Full Speed）は音声方針が未決のため未実装
/// （development_plan.md 14、design.md 16.1）。
abstract final class SpeedMultiplier {
  static const int x1 = 0;
  static const int x2 = 1;
  static const int x4 = 2;
  static const int x8 = 3;
  static const int x16 = 4;
}

/// 空ディスク作成の媒体種別（specification.md FDD-05）。
enum FddMediaType {
  /// 40 cylinder×2 side×16 sector×256 byte（327,680 bytes）。
  d2,

  /// 80 cylinder×2 side×16 sector×256 byte（655,360 bytes）。
  d2dd,
}

/// FDDドライブごとの書込み保護／タイミング補正／CRCエラー無視
/// （specification.md FDD-06）。
///
/// [writeProtected]はディスク単位のランタイム状態、[correctTiming]と
/// [ignoreCrc]はドライブ単位のconfig値で、いずれも即時反映される。
class FddDriveSettings {
  const FddDriveSettings({
    this.writeProtected = false,
    this.correctTiming = false,
    this.ignoreCrc = false,
  });

  final bool writeProtected;
  final bool correctTiming;
  final bool ignoreCrc;

  FddDriveSettings copyWith({
    bool? writeProtected,
    bool? correctTiming,
    bool? ignoreCrc,
  }) {
    return FddDriveSettings(
      writeProtected: writeProtected ?? this.writeProtected,
      correctTiming: correctTiming ?? this.correctTiming,
      ignoreCrc: ignoreCrc ?? this.ignoreCrc,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FddDriveSettings &&
      other.writeProtected == writeProtected &&
      other.correctTiming == correctTiming &&
      other.ignoreCrc == ignoreCrc;

  @override
  int get hashCode => Object.hash(writeProtected, correctTiming, ignoreCrc);
}

/// FD1/FD2の最近使ったファイル1件（specification.md FDD-07）。
///
/// [token]は再選択時に`ExternalFileAccess.resolve`へ渡す永続トークン、
/// [displayName]は表示用の名前（フルパスを含まない）。
typedef FddRecentFile = ({String token, String displayName});

/// 挿入中の媒体の由来（design.md 9.1）。
enum DiskSourceKind {
  /// D88/D77/D8E/1DD。選択バンク以外を保持して同じコンテナへ書き戻せる。
  nativeContainer,

  /// TD0/IMD/DSK/NFD/FDI。原本を変更せず作業用D88として扱う（FDD-09）。
  converted,

  /// headerless raw。convertedと同様、原本を変更しない（FDD-09）。
  raw,
}
