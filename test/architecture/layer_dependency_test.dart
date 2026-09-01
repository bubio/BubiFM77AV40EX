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
      // design.md 11.2 が名指しするplatform境界の抽象だけは例外にする。
      // 「feature層は物理パスを組み立てず、次のplatform境界を利用する」
      // ため、抽象への依存は設計どおりで、禁じるのは実装への依存である。
      allowed: {
        'platform/persistence/preferences_store.dart',
        'platform/persistence/app_data_paths.dart',
        'platform/persistence/cache_workspace.dart',
        'platform/persistence/external_file_access.dart',
        // design.md 3.1 はローカライズを`app`に置く。生成物は他へ依存せず
        // 循環を作らないため、文言の参照だけを許す。
        'app/l10n/generated/app_localizations.dart',
      },
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

  // design.md 3.1、16.1: ネイティブ境界へ触れてよいのは platform/core_ffi だけ。
  // ここを緩めると、featuresがコアの型やFFIへ直接依存し始める。
  const nativeBoundaryPackages = {
    'dart:ffi',
    'package:ffi/',
    'package:bubi_fm77av40ex_core/',
  };
  const nativeBoundaryDirectory = 'lib/platform/core_ffi';

  test('NFR-架構 only platform/core_ffi touches the native boundary', () {
    final violations = <String>[];
    for (final file in _dartFilesUnder('lib')) {
      final path = file.path.replaceAll(Platform.pathSeparator, '/');
      if (path.startsWith('$nativeBoundaryDirectory/')) {
        continue;
      }
      for (final uri in _importedUris(file)) {
        final offender = nativeBoundaryPackages.firstWhere(
          (candidate) => uri == candidate || uri.startsWith(candidate),
          orElse: () => '',
        );
        if (offender.isNotEmpty) {
          violations.add('$path -> $uri');
        }
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'ネイティブ境界は$nativeBoundaryDirectory/へ閉じる\n'
          '違反:\n${violations.join('\n')}',
    );
  });

  for (final rule in rules) {
    test('NFR-架構 ${rule.layer} keeps its dependency direction', () {
      final violations = <String>[];
      for (final file in _dartFilesUnder('lib/${rule.layer}')) {
        for (final target in _importedLibPaths(file)) {
          if (rule.allowed.contains(target)) {
            continue;
          }
          final layer = target.split('/').first;
          if (rule.forbidden.contains(layer)) {
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
    this.allowed = const {},
  });

  final String layer;
  final Set<String> forbidden;

  /// 禁止層のうち、依存してよい個別ファイル（`lib/`起点の相対パス）。
  final Set<String> allowed;

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

/// ファイルが参照する`lib/`起点の相対パスを返す。
Set<String> _importedLibPaths(File file) {
  final paths = <String>{};
  for (final uri in _importedUris(file)) {
    final normalized = _normalizeToLibRelative(uri, file);
    if (normalized == null || !normalized.contains('/')) {
      continue;
    }
    paths.add(normalized);
  }
  return paths;
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
  // 相対importは、必ず絶対パスへ直してから解決する。
  // file.path が相対のままだと解決結果も相対になり、libRoot との
  // 突き合わせがすべて外れて検査が素通りする。
  final resolved = Uri.file(file.absolute.path).resolve(uri).toFilePath();
  final libRoot = Directory('lib').absolute.path;
  if (!resolved.startsWith('$libRoot${Platform.pathSeparator}')) {
    return null;
  }
  return resolved
      .substring(libRoot.length + 1)
      .replaceAll(Platform.pathSeparator, '/');
}
