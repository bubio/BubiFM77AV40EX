import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/persistence/preferences_store.dart';
import 'settings_state.dart';

/// ホスト側だけの設定を`PreferencesStore`へ保存するController
/// （design.md 11.2、11.3、12.2 `Host`）。
///
/// 設定はスキーマ版を持つ。将来の版が増えたときに備え、未知の版
/// （現在の実装より新しい版）を読んだ場合は値を書き換えず、既定値へ
/// 巻き戻さない（後方互換のダウングレード読み込みでデータを壊さない）。
class SettingsController extends Notifier<SettingsState> {
  SettingsController({required this.preferences});

  final PreferencesStore preferences;

  /// 現在このアプリが書き出すスキーマ版。
  ///
  /// 版を上げるときはここでの移行判断を追加し、後方のコードだけで
  /// 仕様を変えない。
  static const int currentSchemaVersion = 1;

  static const String _localeModeKey = 'settings.localeMode';
  static const String _masterVolumeKey = 'settings.masterVolume';

  @override
  SettingsState build() {
    final storedVersion =
        preferences.getInt(PreferencesStore.schemaVersionKey) ?? 0;
    if (storedVersion > currentSchemaVersion) {
      // 未知の将来版。このアプリが理解できない鍵が増えている可能性が
      // あるため、把握している鍵だけを読み、版そのものは書き換えない。
      return _readKnownKeys();
    }
    // storedVersion == 0（鍵なし = 初回起動）でも、
    // storedVersion == currentSchemaVersion でも、既知の鍵をそのまま
    // 読めばよい。版0からの移行は「鍵がなければ既定値」で足りるため、
    // 個別の移行手順は不要である。
    final state = _readKnownKeys();
    if (storedVersion != currentSchemaVersion) {
      unawaited(
        preferences.setInt(
          PreferencesStore.schemaVersionKey,
          currentSchemaVersion,
        ),
      );
    }
    return state;
  }

  SettingsState _readKnownKeys() {
    return SettingsState(
      localeMode: _readLocaleMode(),
      masterVolume: preferences.getDouble(_masterVolumeKey) ?? 1.0,
    );
  }

  AppLocaleMode _readLocaleMode() {
    return switch (preferences.getString(_localeModeKey)) {
      'english' => AppLocaleMode.english,
      'japanese' => AppLocaleMode.japanese,
      _ => AppLocaleMode.system,
    };
  }

  /// UI言語を変える（design.md 12.3「日英切替時はカタログを再構築」）。
  Future<void> setLocaleMode(AppLocaleMode mode) async {
    if (state.localeMode == mode) {
      return;
    }
    await preferences.setString(_localeModeKey, mode.name);
    state = state.copyWith(localeMode: mode);
  }

  /// マスター音量を変える。0.0から1.0へ丸める。
  Future<void> setMasterVolume(double volume) async {
    final clamped = volume.clamp(0.0, 1.0).toDouble();
    if (state.masterVolume == clamped) {
      return;
    }
    await preferences.setDouble(_masterVolumeKey, clamped);
    state = state.copyWith(masterVolume: clamped);
  }
}

final settingsControllerProvider =
    NotifierProvider<SettingsController, SettingsState>(
      () => throw UnimplementedError('appがoverrideWithで組み立てる'),
    );
