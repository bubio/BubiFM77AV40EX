// 依存パッケージのライセンス文書を1ファイルへ集約する。
//
// `.dart_tool/package_config.json` を正とし、各パッケージの LICENSE 系
// ファイルを連結する。配布物へ同梱するライセンス一覧の生成に使う。
//
// usage: fvm dart run tool/collect_licenses.dart <output-path>
import 'dart:convert';
import 'dart:io';

const _licenseFileNames = <String>[
  'LICENSE',
  'LICENSE.md',
  'LICENSE.txt',
  'COPYING',
];

Future<void> main(List<String> args) async {
  final outputPath = args.isNotEmpty
      ? args.first
      : 'build/licenses/THIRD_PARTY_LICENSES.txt';

  final configFile = File('.dart_tool/package_config.json');
  if (!configFile.existsSync()) {
    stderr.writeln('package_config.json がありません。先に pub get を実行してください。');
    exitCode = 1;
    return;
  }

  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  final packages =
      (config['packages'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .where((package) => package['name'] != 'bubi_fm77av40ex')
          .toList()
        ..sort((a, b) => (a['name'] as String).compareTo(b['name'] as String));

  final buffer = StringBuffer()
    ..writeln('BubiFM77AV40EX third-party licenses')
    ..writeln()
    ..writeln('エミュレーションコアのライセンスは本一覧とは別に配布物へ同梱する。')
    ..writeln();

  final missing = <String>[];
  for (final package in packages) {
    final name = package['name'] as String;
    final root = configFile.uri.resolve(package['rootUri'] as String);
    final text = _readLicense(Directory.fromUri(root));
    if (text == null) {
      missing.add(name);
      continue;
    }
    buffer
      ..writeln('=' * 72)
      ..writeln(name)
      ..writeln('=' * 72)
      ..writeln()
      ..writeln(text.trim())
      ..writeln();
  }

  if (missing.isNotEmpty) {
    buffer
      ..writeln('=' * 72)
      ..writeln('ライセンスファイルを検出できなかったパッケージ')
      ..writeln('=' * 72)
      ..writeln();
    for (final name in missing) {
      buffer.writeln('- $name');
    }
  }

  final output = File(outputPath);
  output.parent.createSync(recursive: true);
  output.writeAsStringSync(buffer.toString());
  stdout.writeln(
    '${packages.length} packages, ${missing.length} without license file',
  );
}

String? _readLicense(Directory root) {
  if (!root.existsSync()) {
    return null;
  }
  for (final name in _licenseFileNames) {
    final file = File(
      '${root.path}${root.path.endsWith(Platform.pathSeparator) ? '' : Platform.pathSeparator}$name',
    );
    if (file.existsSync()) {
      return file.readAsStringSync();
    }
  }
  return null;
}
