import 'dart:io';

import 'package:flutter/widgets.dart';

import 'app/bootstrap.dart';
import 'app/cli_args.dart';
import 'emulator/rom/rom_inventory.dart';
import 'emulator/rom/rom_requirement.dart';
import 'emulator/session_state.dart';
import 'platform/persistence/file_system_rom_scanner.dart';
import 'platform/persistence/os_app_data_paths.dart';

Future<void> main(List<String> args) async {
  final parsed = parseCliArgs(args);
  switch (parsed) {
    case CliHelpRequested(:final usage):
      stdout.writeln(usage);
      exit(0);
    case CliSyntaxError(:final message):
      stderr.writeln(message);
      stderr.writeln('Use -h for usage.');
      exit(2);
    case CliParsedOptions(:final options):
      WidgetsFlutterBinding.ensureInitialized();
      final resolvedOptions = await _resolveAndValidate(options);
      // platform実装の組み立てはappの責務（design.md 3.1）。
      runApp(await buildApp(cliOptions: resolvedOptions));
  }
}

/// CLIで指定された媒体パスとROM起動可否をGUI表示前に検証する
/// （specification.md 7.9、design.md「CLI（APP-05）の実装方式」）。
///
/// バンク番号が実際にそのファイルへ存在するかはネイティブコア
/// （`getFddBankInfo`）でしか分からず、それにはセッション起動が要るため
/// ここでは検証しない（GUI起動後の挿入時にexit(3)する、既知の制約）。
Future<CliOptions> _resolveAndValidate(CliOptions options) async {
  final workingDirectory = Directory.current.path;
  final homeDirectory = Platform.environment['HOME'];
  final resolvedMedia = <CliMediaSpec>[];
  for (final spec in options.media) {
    final path = resolveCliPath(
      spec.path,
      workingDirectory: workingDirectory,
      homeDirectory: homeDirectory,
    );
    if (!File(path).existsSync()) {
      stderr.writeln('Media error: file not found "${spec.path}".');
      exit(3);
    }
    resolvedMedia.add(CliMediaSpec(path: path, bank: spec.bank));
  }

  final bootMode = options.bootMode;
  if (bootMode != null) {
    final appDataPaths = OsAppDataPaths();
    const scanner = FileSystemRomScanner();
    try {
      final romsDirectoryPath = await appDataPaths.romsDirectoryPath();
      final probes = await scanner.scan(
        directoryPath: romsDirectoryPath,
        fileNames: {
          for (final requirement in fm77av40exRomRequirements)
            ...requirement.fileNames,
        },
        computeHashes: false,
      );
      final inventory = RomInventory.evaluate(probes: probes);
      final canBoot = bootMode == BootMode.dos
          ? inventory.canBootDos
          : inventory.canBootBasic;
      if (!canBoot) {
        stderr.writeln('ROM error: required ROM files are missing or invalid.');
        exit(4);
      }
    } on Object catch (error) {
      stderr.writeln('ROM error: $error');
      exit(4);
    }
  }

  return options.withMedia(resolvedMedia);
}
