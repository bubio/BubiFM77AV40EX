import 'package:bubi_fm77av40ex/emulator/rom/rom_inventory.dart';
import 'package:bubi_fm77av40ex/emulator/rom/rom_manifest.dart';
import 'package:bubi_fm77av40ex/emulator/rom/rom_probe.dart';
import 'package:bubi_fm77av40ex/emulator/rom/rom_requirement.dart';
import 'package:bubi_fm77av40ex/emulator/rom/rom_status.dart';
import 'package:flutter_test/flutter_test.dart';

const int kib = 1024;

/// 起動必須6ファイルの正常な実測値。
List<RomProbe> bootRequiredProbes() => [
  RomProbe(fileName: 'INITIATE.ROM', sizeInBytes: 8 * kib, readable: true),
  RomProbe(fileName: 'SUBSYS_A.ROM', sizeInBytes: 8 * kib, readable: true),
  RomProbe(fileName: 'SUBSYS_B.ROM', sizeInBytes: 8 * kib, readable: true),
  RomProbe(fileName: 'SUBSYS_C.ROM', sizeInBytes: 10 * kib, readable: true),
  RomProbe(fileName: 'SUBSYSCG.ROM', sizeInBytes: 8 * kib, readable: true),
  RomProbe(fileName: 'EXTSUB.ROM', sizeInBytes: 48 * kib, readable: true),
];

const fbasic302 = RomProbe(
  fileName: 'FBASIC302.ROM',
  sizeInBytes: 31 * kib,
  readable: true,
);

void main() {
  group('SYS-01 起動必須ROM', () {
    test('6ファイルが揃えばDOSで起動できる', () {
      final inventory = RomInventory.evaluate(probes: bootRequiredProbes());
      expect(inventory.canBoot, isTrue);
      expect(inventory.canBootDos, isTrue);
      expect(
        inventory.bootBlockingProblems.map((e) => e.requirement.id),
        isEmpty,
      );
    });

    test('1つ欠けると全モードが止まる', () {
      final probes = bootRequiredProbes()
        ..removeWhere((p) => p.fileName == 'EXTSUB.ROM');
      final inventory = RomInventory.evaluate(probes: probes);
      expect(inventory.canBoot, isFalse);
      expect(inventory.canBootDos, isFalse);
      expect(inventory.canBootBasic, isFalse);
      expect(inventory.entryFor('extsub')!.status, RomStatus.missing);
    });

    test('サイズ違いは wrongSize として起動を止める', () {
      final probes = bootRequiredProbes()
        ..removeWhere((p) => p.fileName == 'SUBSYS_C.ROM')
        ..add(
          const RomProbe(
            fileName: 'SUBSYS_C.ROM',
            sizeInBytes: 8 * kib,
            readable: true,
          ),
        );
      final inventory = RomInventory.evaluate(probes: probes);
      final entry = inventory.entryFor('subsysC')!;
      expect(entry.status, RomStatus.wrongSize);
      expect(entry.actualSizeInBytes, 8 * kib);
      expect(inventory.canBoot, isFalse);
    });

    test('読めないファイルは unreadable として区別する', () {
      final probes = bootRequiredProbes()
        ..removeWhere((p) => p.fileName == 'INITIATE.ROM')
        ..add(const RomProbe.unreadable('INITIATE.ROM'));
      final inventory = RomInventory.evaluate(probes: probes);
      expect(inventory.entryFor('initiate')!.status, RomStatus.unreadable);
      expect(inventory.canBoot, isFalse);
    });
  });

  group('SYS-04 F-BASIC ROMとブートモード', () {
    test('F-BASICがなくてもDOSは起動でき、BASICだけが止まる', () {
      final inventory = RomInventory.evaluate(probes: bootRequiredProbes());
      expect(inventory.canBootDos, isTrue);
      expect(inventory.canBootBasic, isFalse);
      expect(inventory.entryFor('fbasic')!.status, RomStatus.missing);
      // BASICだけを止め、全モードの停止としては数えない。
      expect(inventory.bootBlockingProblems, isEmpty);
      expect(inventory.basicBlockingProblems.map((e) => e.requirement.id), [
        'fbasic',
      ]);
    });

    test('F-BASICが揃えばBASICでも起動できる', () {
      final inventory = RomInventory.evaluate(
        probes: [...bootRequiredProbes(), fbasic302],
      );
      expect(inventory.canBootBasic, isTrue);
    });

    test('候補が複数あるときは仕様の優先順で採る', () {
      final inventory = RomInventory.evaluate(
        probes: [
          ...bootRequiredProbes(),
          const RomProbe(
            fileName: 'FBASIC30.ROM',
            sizeInBytes: 31 * kib,
            readable: true,
          ),
          const RomProbe(
            fileName: 'FBASIC301.ROM',
            sizeInBytes: 31 * kib,
            readable: true,
          ),
          fbasic302,
        ],
      );
      expect(inventory.entryFor('fbasic')!.fileName, 'FBASIC302.ROM');
    });

    test('優先度の高い候補が壊れていれば次の候補を採る', () {
      final inventory = RomInventory.evaluate(
        probes: [
          ...bootRequiredProbes(),
          const RomProbe(
            fileName: 'FBASIC302.ROM',
            sizeInBytes: 1,
            readable: true,
          ),
          const RomProbe(
            fileName: 'FBASIC301.ROM',
            sizeInBytes: 31 * kib,
            readable: true,
          ),
        ],
      );
      final entry = inventory.entryFor('fbasic')!;
      expect(entry.fileName, 'FBASIC301.ROM');
      expect(entry.status, RomStatus.sizeOnly);
      expect(inventory.canBootBasic, isTrue);
    });

    test('KANJI1.ROM がなければ KANJI.ROM を使う', () {
      final inventory = RomInventory.evaluate(
        probes: [
          ...bootRequiredProbes(),
          const RomProbe(
            fileName: 'KANJI.ROM',
            sizeInBytes: 128 * kib,
            readable: true,
          ),
        ],
      );
      final entry = inventory.entryFor('kanji1')!;
      expect(entry.fileName, 'KANJI.ROM');
      expect(entry.isUsable, isTrue);
    });
  });

  group('SYS-01 任意ROM', () {
    test('欠落しても起動を止めず、使えない機能だけを外す', () {
      final inventory = RomInventory.evaluate(probes: bootRequiredProbes());
      expect(inventory.canBootDos, isTrue);
      expect(inventory.availableFeatures, isEmpty);
      expect(inventory.bootBlockingProblems, isEmpty);
      expect(
        inventory.warnings.map((e) => e.requirement.id),
        containsAll(['kanji1', 'kanji2', 'dictionary']),
      );
    });

    test('揃った任意ROMだけが機能として現れる', () {
      final inventory = RomInventory.evaluate(
        probes: [
          ...bootRequiredProbes(),
          const RomProbe(
            fileName: 'KANJI1.ROM',
            sizeInBytes: 128 * kib,
            readable: true,
          ),
          const RomProbe(
            fileName: 'DICROM.ROM',
            sizeInBytes: 256 * kib,
            readable: true,
          ),
        ],
      );
      expect(inventory.availableFeatures, {
        RomFeature.kanjiLevel1,
        RomFeature.dictionary,
      });
    });
  });

  group('NFR-07 SHA-256 manifest', () {
    const digest =
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

    test('manifestがなければ sizeOnly として起動を許可する', () {
      final inventory = RomInventory.evaluate(probes: bootRequiredProbes());
      expect(inventory.entryFor('initiate')!.status, RomStatus.sizeOnly);
      expect(inventory.hasUnverifiedRoms, isTrue);
      expect(inventory.canBoot, isTrue);
    });

    test('一致すれば verified になる', () {
      final inventory = RomInventory.evaluate(
        probes: [
          const RomProbe(
            fileName: 'INITIATE.ROM',
            sizeInBytes: 8 * kib,
            readable: true,
            sha256: digest,
          ),
        ],
        manifest: RomManifest.fromEntries(const [
          RomManifestEntry(
            fileName: 'INITIATE.ROM',
            sizeInBytes: 8 * kib,
            sha256: digest,
          ),
        ]),
      );
      expect(inventory.entryFor('initiate')!.status, RomStatus.verified);
    });

    test('不一致は hashMismatch として起動を止める', () {
      final inventory = RomInventory.evaluate(
        probes: [
          ...bootRequiredProbes().where((p) => p.fileName != 'INITIATE.ROM'),
          const RomProbe(
            fileName: 'INITIATE.ROM',
            sizeInBytes: 8 * kib,
            readable: true,
            sha256: digest,
          ),
        ],
        manifest: RomManifest.fromEntries([
          RomManifestEntry(
            fileName: 'INITIATE.ROM',
            sizeInBytes: 8 * kib,
            sha256: 'ff' * 32,
          ),
        ]),
      );
      expect(inventory.entryFor('initiate')!.status, RomStatus.hashMismatch);
      expect(inventory.canBoot, isFalse);
    });

    test('照合対象があるのに未計算なら verified と言わない', () {
      final inventory = RomInventory.evaluate(
        probes: [
          const RomProbe(
            fileName: 'INITIATE.ROM',
            sizeInBytes: 8 * kib,
            readable: true,
          ),
        ],
        manifest: RomManifest.fromEntries(const [
          RomManifestEntry(
            fileName: 'INITIATE.ROM',
            sizeInBytes: 8 * kib,
            sha256: digest,
          ),
        ]),
      );
      expect(inventory.entryFor('initiate')!.status, RomStatus.sizeOnly);
    });

    test('JSONから読める', () {
      final manifest = RomManifest.fromJson({
        'version': 1,
        'roms': [
          {
            'fileName': 'INITIATE.ROM',
            'sizeInBytes': 8192,
            'sha256': digest.toUpperCase(),
          },
        ],
      });
      expect(manifest.entryFor('initiate.rom')!.sha256, digest);
      expect(manifest.entryFor('SUBSYS_A.ROM'), isNull);
    });

    test('形の違うJSONは FormatException にする', () {
      expect(
        () => RomManifest.fromJson({'version': 1}),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => RomManifest.fromJson({
          'roms': [
            {'fileName': 'A.ROM'},
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('NFR-07 診断に残す情報', () {
    test('検証結果はファイル名だけを持ち、フルパスを持たない', () {
      final inventory = RomInventory.evaluate(probes: bootRequiredProbes());
      for (final entry in inventory.entries) {
        expect(entry.fileName, isNot(contains('/')));
        expect(entry.fileName, isNot(contains(r'\')));
      }
    });
  });

  group('カタログ', () {
    test('仕様書第6章の10件をIDの重複なく定義している', () {
      expect(fm77av40exRomRequirements, hasLength(10));
      final ids = fm77av40exRomRequirements.map((r) => r.id).toSet();
      expect(ids, hasLength(10));
    });

    test('起動必須は6件、BASIC条件必須は1件', () {
      int countOf(RomRole role) =>
          fm77av40exRomRequirements.where((r) => r.role == role).length;
      expect(countOf(RomRole.bootRequired), 6);
      expect(countOf(RomRole.basicRequired), 1);
      expect(countOf(RomRole.optional), 3);
    });

    test('任意ROMには無効化する機能が対応づいている', () {
      for (final requirement in fm77av40exRomRequirements) {
        if (requirement.role == RomRole.optional) {
          expect(requirement.feature, isNotNull, reason: requirement.id);
        } else {
          expect(requirement.feature, isNull, reason: requirement.id);
        }
      }
    });
  });
}
