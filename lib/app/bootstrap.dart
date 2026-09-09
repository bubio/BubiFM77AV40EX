import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../emulator/rom/rom_manifest.dart';
import '../emulator/session_state.dart';
import '../features/display/fullscreen_controller.dart';
import '../features/display/screenshot_service.dart';
import '../features/display/window_scale_controller.dart';
import '../features/input/joystick_assignment_controller.dart';
import '../features/input/joystick_source.dart';
import '../features/session/emulator_controller.dart';
import '../features/session/rom_settings_controller.dart';
import '../features/session/session_providers.dart';
import '../features/settings/settings_controller.dart';
import '../platform/persistence/file_system_rom_scanner.dart';
import '../platform/persistence/os_app_data_paths.dart';
import '../platform/persistence/os_cache_workspace.dart';
import '../platform/persistence/os_external_file_access.dart';
import '../platform/persistence/os_folder_reveal.dart';
import '../platform/persistence/os_window_chrome.dart';
import '../platform/persistence/os_window_scale.dart';
import '../platform/audio/fdd_mechanical_audio_sink.dart';
import '../platform/audio/recording_audio_sink.dart';
import '../platform/core_ffi/bubi_audio_sink.dart';
import '../platform/core_ffi/bubi_video_texture_attacher.dart';
import '../platform/core_ffi/ffi_emulator_session.dart';
import '../platform/persistence/os_preferences_store.dart';
import 'app.dart';
import 'cli_args.dart';

/// 起動時にplatform実装を組み立て、featureのProviderへ差し込む。
///
/// featureはplatform実装を知らない（design.md 3.1）。組み立てを行うのは
/// `app`だけであり、依存の向きはここで一度だけ閉じる。
///
/// Riverpod 3の`Override`型は公開されていないため、上書き一覧を返さず
/// 組み立て済みのWidgetを返す。試験は必要な実装を自分で差し込む。
Future<Widget> buildApp({
  RomManifest? romManifest,
  CliOptions cliOptions = const CliOptions(),
}) async {
  final preferences = await OsPreferencesStore.open();
  final appDataPaths = OsAppDataPaths();
  const scanner = FileSystemRomScanner();
  const reveal = OsFolderReveal();
  final externalFileAccess = OsExternalFileAccess();
  final cacheWorkspace = OsCacheWorkspace(appDataPaths: appDataPaths);
  await cacheWorkspace.purgeAbandonedWorkspaces();

  return ProviderScope(
    overrides: [
      emulatorControllerProvider.overrideWith(
        () => EmulatorController(
          appDataPaths: appDataPaths,
          externalFileAccess: externalFileAccess,
          cacheWorkspace: cacheWorkspace,
          preferences: preferences,
          createSession:
              ({
                required String homeDir,
                String? romDir,
                BootMode bootMode = BootMode.basic,
              }) {
                // FDD内部機構音（AUD-04）はBubiAudioSinkを包む
                // デコレーターとして混ぜ込む。同一インスタンスをPCM出力先
                // （audio）と機構音制御の受け口（fddMechanicalSound）の
                // 両方として渡す（design.md 7.1）。さらに外側を音声録音
                // （AUD-06）のRecordingAudioSinkで包み、最終ミキサー直後の
                // PCMを録音点にする（design.md 7.2）。
                final fddSink = FddMechanicalAudioSink(BubiAudioSink());
                final recordingSink = RecordingAudioSink(fddSink);
                return FfiEmulatorSession.create(
                  homeDir: homeDir,
                  romDir: romDir,
                  bootMode: bootMode,
                  textures: const BubiVideoTextureAttacher(),
                  audio: recordingSink,
                  fddMechanicalSound: fddSink,
                  recording: recordingSink,
                );
              },
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
      settingsControllerProvider.overrideWith(
        () => SettingsController(preferences: preferences),
      ),
      fullscreenControllerProvider.overrideWith(
        () => FullscreenController(windowChrome: OsWindowChrome()),
      ),
      windowScaleControllerProvider.overrideWith(
        () => WindowScaleController(windowScale: OsWindowScale()),
      ),
      joystickAssignmentControllerProvider.overrideWith(
        () => JoystickAssignmentController(
          source: const GamepadsJoystickSource(),
        ),
      ),
      screenshotServiceProvider.overrideWithValue(
        ScreenshotService(appDataPaths: appDataPaths),
      ),
      cliOptionsProvider.overrideWithValue(cliOptions),
    ],
    child: const BubiFm77Av40ExApp(),
  );
}
