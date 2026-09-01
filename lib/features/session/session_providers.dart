import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'rom_settings_controller.dart';
import 'rom_settings_state.dart';

/// ROM設定のController。
///
/// 依存（`ExternalFileAccess`、`PreferencesStore`、`RomScanner`）は
/// `app`が起動時に差し込む。featureはplatform実装を知らない
/// （design.md 3.1）。
final romSettingsControllerProvider =
    NotifierProvider<RomSettingsController, RomSettingsState>(
      () => throw UnimplementedError(
        'romSettingsControllerProvider は app が上書きする。',
      ),
    );
