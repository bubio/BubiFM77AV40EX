import 'package:bubi_fm77av40ex/features/settings/settings_controller.dart';
import 'package:bubi_fm77av40ex/features/settings/settings_state.dart';
import 'package:bubi_fm77av40ex/platform/persistence/preferences_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../session/fakes.dart';

/// 設定スキーマの移行（design.md 11.2、12.2 `Host`）。
void main() {
  late FakePreferencesStore preferences;
  late ProviderContainer container;

  setUp(() {
    preferences = FakePreferencesStore();
    container = ProviderContainer(
      overrides: [
        settingsControllerProvider.overrideWith(
          () => SettingsController(preferences: preferences),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  test('鍵が何もなければ既定値を使い、版をv1として書き込む', () {
    final state = container.read(settingsControllerProvider);

    expect(state.localeMode, AppLocaleMode.system);
    expect(state.masterVolume, 1.0);
    expect(
      preferences.values[PreferencesStore.schemaVersionKey],
      SettingsController.currentSchemaVersion,
    );
  });

  test('自分より新しい未知の版を読んでも、既知の鍵はそのまま使い版を書き換えない', () {
    preferences.values[PreferencesStore.schemaVersionKey] =
        SettingsController.currentSchemaVersion + 1;
    preferences.values['settings.localeMode'] = 'english';
    preferences.values['settings.masterVolume'] = 0.5;

    final state = container.read(settingsControllerProvider);

    expect(state.localeMode, AppLocaleMode.english);
    expect(state.masterVolume, 0.5);
    expect(
      preferences.values[PreferencesStore.schemaVersionKey],
      SettingsController.currentSchemaVersion + 1,
    );
  });

  test('言語を変えると保存し、次回はその値を読む', () async {
    await container
        .read(settingsControllerProvider.notifier)
        .setLocaleMode(AppLocaleMode.japanese);

    expect(
      container.read(settingsControllerProvider).localeMode,
      AppLocaleMode.japanese,
    );
    expect(preferences.values['settings.localeMode'], 'japanese');
  });

  test('マスター音量は0.0から1.0へ丸めて保存する', () async {
    await container
        .read(settingsControllerProvider.notifier)
        .setMasterVolume(1.5);
    expect(container.read(settingsControllerProvider).masterVolume, 1.0);

    await container
        .read(settingsControllerProvider.notifier)
        .setMasterVolume(-0.2);
    expect(container.read(settingsControllerProvider).masterVolume, 0.0);
  });
}
