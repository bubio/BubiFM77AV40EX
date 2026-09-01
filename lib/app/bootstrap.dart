import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:bubi_fm77av40ex_platform/bubi_fm77av40ex_platform.dart';

import '../emulator/rom/rom_manifest.dart';
import '../emulator/session_state.dart';
import '../features/session/emulator_controller.dart';
import '../features/session/rom_settings_controller.dart';
import '../features/session/session_providers.dart';
import '../platform/persistence/file_system_rom_scanner.dart';
import '../platform/persistence/os_app_data_paths.dart';
import '../platform/core_ffi/ffi_emulator_session.dart';
import '../platform/persistence/os_preferences_store.dart';
import 'app.dart';

/// 起動時にplatform実装を組み立て、featureのProviderへ差し込む。
///
/// featureはplatform実装を知らない（design.md 3.1）。組み立てを行うのは
/// `app`だけであり、依存の向きはここで一度だけ閉じる。
///
/// Riverpod 3の`Override`型は公開されていないため、上書き一覧を返さず
/// 組み立て済みのWidgetを返す。試験は必要な実装を自分で差し込む。
Future<Widget> buildApp({RomManifest? romManifest}) async {
  final preferences = await OsPreferencesStore.open();
  final appDataPaths = OsAppDataPaths();
  const scanner = FileSystemRomScanner();
  const reveal = FileManagerReveal();

  return ProviderScope(
    overrides: [
      emulatorControllerProvider.overrideWith(
        () => EmulatorController(
          appDataPaths: appDataPaths,
          createSession:
              ({
                required String homeDir,
                String? romDir,
                BootMode bootMode = BootMode.basic,
              }) => FfiEmulatorSession.create(
                homeDir: homeDir,
                romDir: romDir,
                bootMode: bootMode,
              ),
        ),
      ),
      romSettingsControllerProvider.overrideWith(
        () => RomSettingsController(
          appDataPaths: appDataPaths,
          preferences: preferences,
          scanner: scanner,
          manifest: romManifest,
          revealFolder: reveal.reveal,
        ),
      ),
    ],
    child: const BubiFm77Av40ExApp(),
  );
}
