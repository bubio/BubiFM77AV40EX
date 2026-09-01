import 'rom_manifest.dart';
import 'rom_probe.dart';
import 'rom_requirement.dart';
import 'rom_status.dart';

/// 1つのROM要件に対する検証結果。
class RomInventoryEntry {
  const RomInventoryEntry({
    required this.requirement,
    required this.status,
    this.fileName,
    this.actualSizeInBytes,
  });

  final RomRequirement requirement;
  final RomStatus status;

  /// 採用したファイル名。見つからなかった場合はnull。
  ///
  /// フルパスは持たない。通常ログへ利用者名を含むパスを残さない（NFR-07）。
  final String? fileName;

  /// 実サイズ。分からない場合はnull。
  final int? actualSizeInBytes;

  bool get isUsable => status.isUsable;
}

/// ROMディレクトリ全体の検証結果（design.md 10）。
///
/// ROM本体をDartヒープへ載せず、コアへはディレクトリのOSパスだけを渡す。
class RomInventory {
  const RomInventory(this.entries);

  /// 実測値と要件を突き合わせる。
  ///
  /// [manifest] がnullまたは空なら、名前とサイズが合ったROMは
  /// [RomStatus.sizeOnly] とし、起動を許可する（specification.md 6）。
  factory RomInventory.evaluate({
    required Iterable<RomProbe> probes,
    List<RomRequirement> requirements = fm77av40exRomRequirements,
    RomManifest? manifest,
  }) {
    final byName = <String, RomProbe>{
      for (final probe in probes) probe.fileName.toUpperCase(): probe,
    };

    return RomInventory([
      for (final requirement in requirements)
        _evaluateOne(requirement, byName, manifest),
    ]);
  }

  final List<RomInventoryEntry> entries;

  RomInventoryEntry? entryFor(String id) {
    for (final entry in entries) {
      if (entry.requirement.id == id) {
        return entry;
      }
    }
    return null;
  }

  Iterable<RomInventoryEntry> _withRole(RomRole role) =>
      entries.where((entry) => entry.requirement.role == role);

  /// 起動必須6ファイルがすべて使えるか。DOSモードの起動条件でもある。
  bool get canBoot => _withRole(RomRole.bootRequired).every((e) => e.isUsable);

  /// BASICモードで起動できるか。起動必須に加えてF-BASIC ROMが要る。
  bool get canBootBasic =>
      canBoot && _withRole(RomRole.basicRequired).every((e) => e.isUsable);

  /// DOSモードで起動できるか。F-BASIC ROMは要らない（specification.md 6）。
  bool get canBootDos => canBoot;

  /// 使える任意ROMが提供する機能。
  Set<RomFeature> get availableFeatures => {
    for (final entry in _withRole(RomRole.optional))
      if (entry.isUsable && entry.requirement.feature != null)
        entry.requirement.feature!,
  };

  /// 全モードの起動を止める異常（起動必須6ファイル）。
  List<RomInventoryEntry> get bootBlockingProblems =>
      _withRole(RomRole.bootRequired).where((e) => e.status.isProblem).toList();

  /// BASICモードだけを止める異常（F-BASIC ROM）。
  List<RomInventoryEntry> get basicBlockingProblems =>
      _withRole(RomRole.basicRequired)
          .where((e) => e.status.isProblem)
          .toList();

  /// 起動は止めず、機能が減るだけの異常（任意ROM）。
  List<RomInventoryEntry> get warnings =>
      _withRole(RomRole.optional).where((e) => e.status.isProblem).toList();

  /// 承認済みmanifestで照合できていないROMがあるか。UIへ未検証と表示する。
  bool get hasUnverifiedRoms =>
      entries.any((entry) => entry.status == RomStatus.sizeOnly);
}

RomInventoryEntry _evaluateOne(
  RomRequirement requirement,
  Map<String, RomProbe> byName,
  RomManifest? manifest,
) {
  // 候補名を優先順に見て、最初に「使える」ものを採る。
  // 使えるものがなければ、最も情報量の多い異常を報告する。
  RomInventoryEntry? firstProblem;

  for (final fileName in requirement.fileNames) {
    final probe = byName[fileName.toUpperCase()];
    if (probe == null) {
      continue;
    }
    final entry = _evaluateProbe(requirement, probe, manifest);
    if (entry.isUsable) {
      return entry;
    }
    firstProblem ??= entry;
  }

  return firstProblem ??
      RomInventoryEntry(requirement: requirement, status: RomStatus.missing);
}

RomInventoryEntry _evaluateProbe(
  RomRequirement requirement,
  RomProbe probe,
  RomManifest? manifest,
) {
  if (!probe.readable) {
    return RomInventoryEntry(
      requirement: requirement,
      status: RomStatus.unreadable,
      fileName: probe.fileName,
      actualSizeInBytes: probe.sizeInBytes,
    );
  }
  if (probe.sizeInBytes != requirement.sizeInBytes) {
    return RomInventoryEntry(
      requirement: requirement,
      status: RomStatus.wrongSize,
      fileName: probe.fileName,
      actualSizeInBytes: probe.sizeInBytes,
    );
  }

  final expected = manifest?.entryFor(probe.fileName);
  if (expected == null) {
    // manifest未提供を起動失敗にしない（specification.md 6）。
    return RomInventoryEntry(
      requirement: requirement,
      status: RomStatus.sizeOnly,
      fileName: probe.fileName,
      actualSizeInBytes: probe.sizeInBytes,
    );
  }
  if (probe.sha256 == null) {
    // 照合対象があるのに計算できていない。未検証として扱い、
    // 一致したとは言わない。
    return RomInventoryEntry(
      requirement: requirement,
      status: RomStatus.sizeOnly,
      fileName: probe.fileName,
      actualSizeInBytes: probe.sizeInBytes,
    );
  }
  if (probe.sha256!.toLowerCase() != expected.sha256.toLowerCase()) {
    return RomInventoryEntry(
      requirement: requirement,
      status: RomStatus.hashMismatch,
      fileName: probe.fileName,
      actualSizeInBytes: probe.sizeInBytes,
    );
  }
  return RomInventoryEntry(
    requirement: requirement,
    status: RomStatus.verified,
    fileName: probe.fileName,
    actualSizeInBytes: probe.sizeInBytes,
  );
}
