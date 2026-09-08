import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../emulator/session_state.dart';

/// CLIで指定された1つの媒体（specification.md 7.9）。
///
/// [bank]はD88等のバンク番号を1始まりで表す。省略時はnull。
class CliMediaSpec {
  const CliMediaSpec({required this.path, this.bank});

  final String path;
  final int? bank;

  @override
  bool operator ==(Object other) =>
      other is CliMediaSpec && other.path == path && other.bank == bank;

  @override
  int get hashCode => Object.hash(path, bank);

  @override
  String toString() => 'CliMediaSpec($path, bank: $bank)';
}

/// パース済みのCLIオプション（APP-05）。
///
/// 各設定項目はnull/false=「CLIでは指定されなかった」を表し、起動時に
/// 既定値・永続化済み設定を上書きしない（design.md「CLI（APP-05）の
/// 実装方式」）。
class CliOptions {
  const CliOptions({
    this.bootMode,
    this.cpuType,
    this.speedMultiplier,
    this.fullSpeed = false,
    this.cycleSteal,
    this.extendedRam,
    this.syncToHsync,
    this.media = const [],
  });

  final BootMode? bootMode;
  final CpuType? cpuType;

  /// [SpeedMultiplier]のいずれか。未指定はnull。
  final int? speedMultiplier;
  final bool fullSpeed;
  final bool? cycleSteal;
  final bool? extendedRam;
  final bool? syncToHsync;

  /// 最大2件。index 0=FD1、1=FD2（specification.md 7.9）。
  final List<CliMediaSpec> media;

  /// 実行設定の上書きが1つでも指定されたか。
  bool get hasRuntimeOverrides =>
      cpuType != null ||
      speedMultiplier != null ||
      fullSpeed ||
      cycleSteal != null ||
      extendedRam != null ||
      syncToHsync != null;

  CliOptions withMedia(List<CliMediaSpec> media) => CliOptions(
    bootMode: bootMode,
    cpuType: cpuType,
    speedMultiplier: speedMultiplier,
    fullSpeed: fullSpeed,
    cycleSteal: cycleSteal,
    extendedRam: extendedRam,
    syncToHsync: syncToHsync,
    media: media,
  );
}

/// [parseCliArgs]の結果。
sealed class CliParseResult {
  const CliParseResult();
}

/// `-h`/`-help`/`--help`が指定された。
final class CliHelpRequested extends CliParseResult {
  const CliHelpRequested(this.usage);

  final String usage;
}

/// 構文エラー（未知オプション、空引数、不正バンク等）。終了コード2。
final class CliSyntaxError extends CliParseResult {
  const CliSyntaxError(this.message);

  final String message;
}

/// 構文上は正しく解釈できたオプション一式。
final class CliParsedOptions extends CliParseResult {
  const CliParsedOptions(this.options);

  final CliOptions options;
}

/// specification.md 7.9の文法テキスト（英語のみ、design.md「CLI（APP-05）の
/// 実装方式」参照）。
const String cliUsageText = '''
Usage: BubiFM77AV40EX [-option ...] image-file [image-No] [image-file [image-No]]

  image-No           1-based bank number within a multi-bank image (e.g. D88).
                      If omitted for a single multi-bank image, bank 1 is
                      assigned to FD1 and bank 2 (if present) to FD2.

Options (case-insensitive; last one wins for the same setting):
  -basic / -dos                       Boot mode.
  -2mhz / -1.2mhz                     CPU type.
  -x1 / -x2 / -x4 / -x8 / -x16        Speed multiplier.
  -fullspeed                          Unrestricted speed.
  -cycle_steal / -no_cycle_steal      Cycle steal.
  -extram / -no_extram                Extended RAM.
  -hsync / -no_hsync                  HSYNC sync.
  -h / -help / --help                 Show this help and exit.

Exit codes: 0=success or help, 2=syntax error, 3=media error,
4=ROM/boot error, 5=internal error.
''';

const Map<String, BootMode> _bootModeOptions = {
  '-basic': BootMode.basic,
  '-dos': BootMode.dos,
};

const Map<String, CpuType> _cpuTypeOptions = {
  '-2mhz': CpuType.fast,
  '-1.2mhz': CpuType.slow,
};

const Map<String, int> _speedOptions = {
  '-x1': SpeedMultiplier.x1,
  '-x2': SpeedMultiplier.x2,
  '-x4': SpeedMultiplier.x4,
  '-x8': SpeedMultiplier.x8,
  '-x16': SpeedMultiplier.x16,
};

const Set<String> _helpOptions = {'-h', '-help', '--help'};

/// コマンドライン引数をパースする（副作用なし、design.md 8.4）。
CliParseResult parseCliArgs(List<String> args) {
  BootMode? bootMode;
  CpuType? cpuType;
  int? speedMultiplier;
  var fullSpeed = false;
  bool? cycleSteal;
  bool? extendedRam;
  bool? syncToHsync;
  final media = <CliMediaSpec>[];

  var i = 0;
  while (i < args.length) {
    final raw = args[i];
    if (raw.isEmpty) {
      return const CliSyntaxError('Syntax error: empty argument.');
    }
    final lower = raw.toLowerCase();

    if (_helpOptions.contains(lower)) {
      return const CliHelpRequested(cliUsageText);
    }
    if (_bootModeOptions.containsKey(lower)) {
      bootMode = _bootModeOptions[lower];
      i++;
      continue;
    }
    if (_cpuTypeOptions.containsKey(lower)) {
      cpuType = _cpuTypeOptions[lower];
      i++;
      continue;
    }
    if (_speedOptions.containsKey(lower)) {
      speedMultiplier = _speedOptions[lower];
      i++;
      continue;
    }
    switch (lower) {
      case '-fullspeed':
        fullSpeed = true;
        i++;
        continue;
      case '-cycle_steal':
        cycleSteal = true;
        i++;
        continue;
      case '-no_cycle_steal':
        cycleSteal = false;
        i++;
        continue;
      case '-extram':
        extendedRam = true;
        i++;
        continue;
      case '-no_extram':
        extendedRam = false;
        i++;
        continue;
      case '-hsync':
        syncToHsync = true;
        i++;
        continue;
      case '-no_hsync':
        syncToHsync = false;
        i++;
        continue;
    }

    if (raw.startsWith('-')) {
      return CliSyntaxError('Syntax error: unknown option "$raw".');
    }

    // image-file。3件目以降は無視するが、直後のbank数字は読み飛ばす
    // （パーサー位置の整合を保つ、specification.md 7.9）。
    i++;
    int? bank;
    if (i < args.length && RegExp(r'^[0-9]+$').hasMatch(args[i])) {
      final value = int.parse(args[i]);
      if (value < 1) {
        return CliSyntaxError(
          'Syntax error: invalid bank number "${args[i]}".',
        );
      }
      bank = value;
      i++;
    }
    if (media.length < 2) {
      media.add(CliMediaSpec(path: raw, bank: bank));
    }
  }

  return CliParsedOptions(
    CliOptions(
      bootMode: bootMode,
      cpuType: cpuType,
      speedMultiplier: speedMultiplier,
      fullSpeed: fullSpeed,
      cycleSteal: cycleSteal,
      extendedRam: extendedRam,
      syncToHsync: syncToHsync,
      media: media,
    ),
  );
}

/// 相対パスの解決（プロセスの作業ディレクトリ基準）と`~`展開
/// （specification.md 7.9）。副作用なし・ファイルI/Oなし。
String resolveCliPath(
  String raw, {
  required String workingDirectory,
  String? homeDirectory,
}) {
  var path = raw;
  if (path == '~') {
    return homeDirectory ?? path;
  }
  if (path.startsWith('~/') && homeDirectory != null) {
    path = '$homeDirectory${path.substring(1)}';
  }
  if (path.startsWith('/')) {
    return path;
  }
  return '$workingDirectory/$path';
}

/// `main()`が起動前に組み立てたCLIオプション。`app`が[buildApp]経由で
/// 差し込む（design.md 3.1、他のplatform実装と同じ`overrideWithValue`）。
final cliOptionsProvider = Provider<CliOptions>((ref) => const CliOptions());
