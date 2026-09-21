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

/// オーディオバッファ（design.md 7、Host > Sound）。
///
/// コアが起動時（`EMU`のコンストラクタ）に1度だけ読むため、変更は次回の
/// セッション起動（アプリの再起動、またはセッションの作り直し）まで
/// 反映されない。
enum AudioBufferSize {
  /// 50ms（既定）。
  ms50,

  /// 100ms。
  ms100,

  /// 200ms。
  ms200,

  /// 300ms。
  ms300,
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

/// 標準音声の個別音量チャンネル（specification.md AUD-03）。
///
/// OPN1/OPN2（WHG/THG拡張、AUD-02、P2）とCMT関連チャンネルは含まない。
enum SoundChannel {
  /// 標準OPNのFM部。
  opnFm,

  /// 標準OPNのPSG部（YM2203内蔵SSG）。
  opnPsg,

  /// Beep（1bit PCM）。
  beep,

  /// キーボード操作音（AV系専用）。
  keyboardBeep,

  /// FDDのシーク・ヘッドロード／アンロード機構音。
  fddMechanism,
}

/// 標準音声チャンネルごとの音量（specification.md AUD-03）。
///
/// 各値は0.0〜1.0。マスター音量（design.md 12.4、`SettingsController`）
/// とは別物で、`PreferencesStore`へは永続化しない
/// （`EmulatorController`がセッション内で記憶し、次回`launch()`で
/// 再適用する。[CpuType]/[RunOptionSwitches]と同じ扱い）。
class SoundChannelVolumes {
  const SoundChannelVolumes({
    this.opnFm = 1.0,
    this.opnPsg = 1.0,
    this.beep = 1.0,
    this.keyboardBeep = 1.0,
    this.fddMechanism = 1.0,
  });

  final double opnFm;
  final double opnPsg;
  final double beep;
  final double keyboardBeep;
  final double fddMechanism;

  double operator [](SoundChannel channel) {
    return switch (channel) {
      SoundChannel.opnFm => opnFm,
      SoundChannel.opnPsg => opnPsg,
      SoundChannel.beep => beep,
      SoundChannel.keyboardBeep => keyboardBeep,
      SoundChannel.fddMechanism => fddMechanism,
    };
  }

  SoundChannelVolumes withVolume(SoundChannel channel, double volume) {
    return switch (channel) {
      SoundChannel.opnFm => copyWith(opnFm: volume),
      SoundChannel.opnPsg => copyWith(opnPsg: volume),
      SoundChannel.beep => copyWith(beep: volume),
      SoundChannel.keyboardBeep => copyWith(keyboardBeep: volume),
      SoundChannel.fddMechanism => copyWith(fddMechanism: volume),
    };
  }

  SoundChannelVolumes copyWith({
    double? opnFm,
    double? opnPsg,
    double? beep,
    double? keyboardBeep,
    double? fddMechanism,
  }) {
    return SoundChannelVolumes(
      opnFm: opnFm ?? this.opnFm,
      opnPsg: opnPsg ?? this.opnPsg,
      beep: beep ?? this.beep,
      keyboardBeep: keyboardBeep ?? this.keyboardBeep,
      fddMechanism: fddMechanism ?? this.fddMechanism,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SoundChannelVolumes &&
      other.opnFm == opnFm &&
      other.opnPsg == opnPsg &&
      other.beep == beep &&
      other.keyboardBeep == keyboardBeep &&
      other.fddMechanism == fddMechanism;

  @override
  int get hashCode =>
      Object.hash(opnFm, opnPsg, beep, keyboardBeep, fddMechanism);
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

/// CMTの音声区分（specification.md AUD-07）。原作`.rc`の"Play CMT Noise"/
/// "Play CMT Signal"/"Play CMT Voice"に対応する。標準OPN音量（AUD-03、
/// [SoundChannel]）とは別区分のまま混在させない。
enum CmtSoundKind {
  /// リレー動作音・早送り音（`DATAREC`のNOISEデバイス3種）。
  noise,

  /// テープ信号をそのまま音として再生する経路（`config.sound_tape_signal`）。
  signal,

  /// テープの声（PCM相当）をそのまま音として再生する経路
  /// （`config.sound_tape_voice`）。upstreamの`VM::set_sound_device_volume()`
  /// がこの経路の内部音量（`DATAREC::set_volume(1,...)`）へ配線されておらず、
  /// upstream改変禁止のため独立した音量調整はできない（有効・無効のみ）。
  voice,
}

/// CMTドライブの波形整形設定（specification.md CMT-04）。
///
/// upstreamの`config.wave_shaper[0]`はWAV読込み時に直接読まれる
/// ランタイム状態で、即時反映される。
class CmtDriveSettings {
  const CmtDriveSettings({this.waveShaping = false});

  final bool waveShaping;

  CmtDriveSettings copyWith({bool? waveShaping}) {
    return CmtDriveSettings(waveShaping: waveShaping ?? this.waveShaping);
  }

  @override
  bool operator ==(Object other) =>
      other is CmtDriveSettings && other.waveShaping == waveShaping;

  @override
  int get hashCode => waveShaping.hashCode;
}

/// CMT音声の個別有効化と、ノイズ・信号のみの音量（specification.md AUD-07）。
///
/// [voiceEnabled]は切替できるが、[voice]の音量は独立して調整できない
/// （[CmtSoundKind.voice]のコメント参照）。
class CmtSoundSettings {
  const CmtSoundSettings({
    this.noiseEnabled = false,
    this.signalEnabled = false,
    this.voiceEnabled = false,
    this.noiseVolume = 1.0,
    this.signalVolume = 1.0,
  });

  final bool noiseEnabled;
  final bool signalEnabled;
  final bool voiceEnabled;

  /// 0.0〜1.0。
  final double noiseVolume;

  /// 0.0〜1.0。
  final double signalVolume;

  bool enabledOf(CmtSoundKind kind) => switch (kind) {
    CmtSoundKind.noise => noiseEnabled,
    CmtSoundKind.signal => signalEnabled,
    CmtSoundKind.voice => voiceEnabled,
  };

  CmtSoundSettings withEnabled(CmtSoundKind kind, bool enabled) =>
      switch (kind) {
        CmtSoundKind.noise => copyWith(noiseEnabled: enabled),
        CmtSoundKind.signal => copyWith(signalEnabled: enabled),
        CmtSoundKind.voice => copyWith(voiceEnabled: enabled),
      };

  CmtSoundSettings copyWith({
    bool? noiseEnabled,
    bool? signalEnabled,
    bool? voiceEnabled,
    double? noiseVolume,
    double? signalVolume,
  }) {
    return CmtSoundSettings(
      noiseEnabled: noiseEnabled ?? this.noiseEnabled,
      signalEnabled: signalEnabled ?? this.signalEnabled,
      voiceEnabled: voiceEnabled ?? this.voiceEnabled,
      noiseVolume: noiseVolume ?? this.noiseVolume,
      signalVolume: signalVolume ?? this.signalVolume,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CmtSoundSettings &&
      other.noiseEnabled == noiseEnabled &&
      other.signalEnabled == signalEnabled &&
      other.voiceEnabled == voiceEnabled &&
      other.noiseVolume == noiseVolume &&
      other.signalVolume == signalVolume;

  @override
  int get hashCode => Object.hash(
    noiseEnabled,
    signalEnabled,
    voiceEnabled,
    noiseVolume,
    signalVolume,
  );
}

/// CMTの最近使ったファイル1件（specification.md CMT-05）。
/// [FddRecentFile]と同型（[token]/[displayName]の意味も同じ）。
typedef CmtRecentFile = ({String token, String displayName});
