import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// design.md 3.1 と BluePrint「アーキテクチャ」で固定した依存方向を検査する。
///
/// ```text
/// app      → features / platform（実装の注入のみ）
/// features → emulator API / shared
/// platform → emulator API
/// ```
void main() {
  final rules = <_LayerRule>[
    _LayerRule(
      layer: 'features',
      forbidden: {'platform', 'app'},
      reason: 'featuresはplatform実装とappへ依存しない',
    ),
    _LayerRule(
      layer: 'emulator',
      forbidden: {'platform', 'features', 'app', 'shared'},
      reason: 'emulator APIは他のどの層へも依存しない',
    ),
    _LayerRule(
      layer: 'platform',
      forbidden: {'features', 'app'},
      reason: 'platformはemulator APIとsharedだけへ依存する',
    ),
    _LayerRule(
      layer: 'shared',
      forbidden: {'features', 'platform', 'app', 'emulator'},
      reason: 'sharedは本当に共通なWidgetとユーティリティだけを持つ',
    ),
  ];

  // design.md 11.2: feature層は物理パスを組み立てず、platform境界だけを使う。
  const pathPackages = {'dart:io', 'package:path_provider/', 'package:path/'};

  test('NFR-架構 features never touches OS paths directly', () {
    final violations = <String>[];
    for (final file in _dartFilesUnder('lib/features')) {
      for (final uri in _importedUris(file)) {
        final offender = pathPackages.firstWhere(
          (candidate) => uri == candidate || uri.startsWith(candidate),
          orElse: () => '',
        );
        if (offender.isNotEmpty) {
          violations.add('${file.path} -> $uri');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'featuresはPreferencesStore/AppDataPaths/CacheWorkspace/'
          'ExternalFileAccessを経由する\n違反:\n${violations.join('\n')}',
    );
  });

  for (final rule in rules) {
    test('NFR-架構 ${rule.layer} keeps its dependency direction', () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib/${rule.layer}')) {
        for (final target in _importedLayers(file)) {
          if (rule.forbidden.contains(target)) {
            violations.add('${file.path} -> lib/$target');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason: '${rule.reason}\n違反:\n${violations.join('\n')}',
      );
    });
  }
}

class _LayerRule {
  const _LayerRule({
    required this.layer,
    required this.forbidden,
    required this.reason,
  });

  final String layer;
  final Set<String> forbidden;
  final String reason;
}

Iterable<File> _dartFilesUnder(String path) {
  final directory = Directory(path);
  if (!directory.existsSync()) {
    return const [];
  }
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
}

final RegExp _importPattern = RegExp(
  '''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// ファイルが参照するimport/export URIをそのまま返す。
Set<String> _importedUris(File file) {
  final source = file.readAsStringSync();
  return _importPattern
      .allMatches(source)
      .map((match) => match.group(1)!)
      .toSet();
}

/// ファイルが参照する`lib/`直下の層名を返す。
Set<String> _importedLayers(File file) {
  final layers = <String>{};
  for (final uri in _importedUris(file)) {
    final normalized = _normalizeToLibRelative(uri, file);
    if (normalized == null) {
      continue;
    }
    final segments = normalized.split('/');
    if (segments.length > 1) {
      layers.add(segments.first);
    }
  }
  return layers;
}

/// package: と相対importを`lib/`起点の相対パスへ正規化する。
String? _normalizeToLibRelative(String uri, File file) {
  const packagePrefix = 'package:bubi_fm77av40ex/';
  if (uri.startsWith(packagePrefix)) {
    return uri.substring(packagePrefix.length);
  }
  if (uri.startsWith('dart:') || uri.startsWith('package:')) {
    return null;
  }
  final resolved = Uri.file(file.path).resolve(uri).toFilePath();
  final libRoot = Directory('lib').absolute.path;
  if (!resolved.startsWith('$libRoot${Platform.pathSeparator}')) {
    return null;
  }
  return resolved
      .substring(libRoot.length + 1)
      .replaceAll(Platform.pathSeparator, '/');
}
