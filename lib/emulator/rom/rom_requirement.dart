/// ROMが担う役割。欠落したときの影響範囲を決める。
enum RomRole {
  /// 起動必須。異常なら全モードを停止する。
  bootRequired,

  /// BASICモード条件必須。異常ならBASICモードだけを停止する。
  basicRequired,

  /// 任意。異常なら該当機能を未接続化して警告する。
  optional,
}

/// 欠落したときに使えなくなる機能。[RomRole.optional] でのみ意味を持つ。
enum RomFeature {
  /// 第一水準漢字。
  kanjiLevel1,

  /// 第二水準漢字。
  kanjiLevel2,

  /// 辞書機能（辞書カード）。
  dictionary,
}

/// 1つのROM要件（specification.md 6）。
class RomRequirement {
  const RomRequirement({
    required this.id,
    required this.fileNames,
    required this.sizeInBytes,
    required this.role,
    this.feature,
  });

  /// 表示とテストで使う安定した識別子。
  final String id;

  /// 受け付けるファイル名。**優先順**に並べ、最初に有効なものを採用する。
  /// 空にしない。
  final List<String> fileNames;

  /// 正確なサイズ。1バイトでも違えば [RomStatus.wrongSize] とする。
  final int sizeInBytes;

  final RomRole role;

  /// 欠落時に無効化する機能。[RomRole.optional] のときだけ設定する。
  final RomFeature? feature;

  /// 代表するファイル名。表示に使う。
  String get primaryFileName => fileNames.first;
}

const int _kib = 1024;

/// FM77AV40EXが要求するROM一覧（specification.md 6）。
///
/// サイズはコアの`read_bios`要求量と一致することを確認済み
/// （design.md 16.1「ROMディレクトリとコアの読込み位置」）。
/// 名前と優先順はupstreamの`vm/fm7/fm7_common.h`と一致させる。
const List<RomRequirement> fm77av40exRomRequirements = [
  RomRequirement(
    id: 'initiate',
    fileNames: ['INITIATE.ROM'],
    sizeInBytes: 8 * _kib,
    role: RomRole.bootRequired,
  ),
  RomRequirement(
    id: 'subsysA',
    fileNames: ['SUBSYS_A.ROM'],
    sizeInBytes: 8 * _kib,
    role: RomRole.bootRequired,
  ),
  RomRequirement(
    id: 'subsysB',
    fileNames: ['SUBSYS_B.ROM'],
    sizeInBytes: 8 * _kib,
    role: RomRole.bootRequired,
  ),
  RomRequirement(
    id: 'subsysC',
    fileNames: ['SUBSYS_C.ROM'],
    sizeInBytes: 10 * _kib,
    role: RomRole.bootRequired,
  ),
  RomRequirement(
    id: 'subsysCg',
    fileNames: ['SUBSYSCG.ROM'],
    sizeInBytes: 8 * _kib,
    role: RomRole.bootRequired,
  ),
  RomRequirement(
    id: 'extsub',
    fileNames: ['EXTSUB.ROM'],
    sizeInBytes: 48 * _kib,
    role: RomRole.bootRequired,
  ),
  RomRequirement(
    id: 'fbasic',
    // 左から優先。upstream の探索順（L20→L10→L00→V30）と同じ。
    fileNames: [
      'FBASIC302.ROM',
      'FBASIC301.ROM',
      'FBASIC300.ROM',
      'FBASIC30.ROM',
    ],
    sizeInBytes: 31 * _kib,
    role: RomRole.basicRequired,
  ),
  RomRequirement(
    id: 'kanji1',
    fileNames: ['KANJI1.ROM', 'KANJI.ROM'],
    sizeInBytes: 128 * _kib,
    role: RomRole.optional,
    feature: RomFeature.kanjiLevel1,
  ),
  RomRequirement(
    id: 'kanji2',
    fileNames: ['KANJI2.ROM'],
    sizeInBytes: 128 * _kib,
    role: RomRole.optional,
    feature: RomFeature.kanjiLevel2,
  ),
  RomRequirement(
    id: 'dictionary',
    fileNames: ['DICROM.ROM'],
    sizeInBytes: 256 * _kib,
    role: RomRole.optional,
    feature: RomFeature.dictionary,
  ),
];
