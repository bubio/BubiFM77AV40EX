import 'package:flutter/material.dart';

import '../../features/settings/settings_state.dart';
import '../l10n/generated/app_localizations.dart';

/// `Application > Settings…`が開く設定画面（design.md 12.1、12.2）。
///
/// `Host > Language`と同じ共有コマンド（[onLocaleModeChanged]）へ
/// 接続する（design.md 12.3「Settingsも共通コマンドへ接続する」）。
/// マスター音量はdesign.md 12.4のステータスバー表示に対応する操作面
/// として、ここへ置く。
class SettingsDialog extends StatelessWidget {
  const SettingsDialog({
    super.key,
    required this.l10n,
    required this.localeMode,
    required this.onLocaleModeChanged,
    required this.masterVolume,
    required this.onMasterVolumeChanged,
  });

  final AppLocalizations l10n;
  final AppLocaleMode localeMode;
  final void Function(AppLocaleMode mode) onLocaleModeChanged;
  final double masterVolume;
  final void Function(double volume) onMasterVolumeChanged;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(l10n.menuAppSettings),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.menuHostLanguage,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          RadioGroup<AppLocaleMode>(
            groupValue: localeMode,
            onChanged: (value) {
              if (value != null) {
                onLocaleModeChanged(value);
              }
            },
            child: Column(
              children: [
                for (final mode in AppLocaleMode.values)
                  RadioListTile<AppLocaleMode>(
                    value: mode,
                    title: Text(_localeLabel(mode)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.settingsMasterVolume,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          Slider(
            value: masterVolume,
            onChanged: onMasterVolumeChanged,
            label: '${(masterVolume * 100).round()}%',
          ),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('settingsDialogClose'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.settingsClose),
        ),
      ],
    );
  }

  String _localeLabel(AppLocaleMode mode) {
    return switch (mode) {
      AppLocaleMode.system => l10n.menuLanguageSystem,
      AppLocaleMode.english => l10n.menuLanguageEnglish,
      AppLocaleMode.japanese => l10n.menuLanguageJapanese,
    };
  }
}
