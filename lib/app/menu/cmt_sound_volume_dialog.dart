import 'package:flutter/material.dart';

import '../../emulator/session_state.dart';
import '../l10n/generated/app_localizations.dart';

/// `Device > Sound > CMT Volume…`が開く音量ダイアログ（specification.md
/// AUD-07）。
///
/// CMTノイズ・CMT信号のみを個別に調整する。標準OPN等の音量
/// （[SoundVolumeDialog]、AUD-03）とは別区分のまま混在させない
/// （design.md 7.1）。CMT音声（voice）はupstreamの
/// `VM::set_sound_device_volume()`がCMT音声用の内部音量へ配線しておらず、
/// upstream改変禁止のため独立した音量調整ができない既知の制約のため、
/// ここにはスライダーを出さない（有効・無効はDevice > Soundのチェック
/// 項目で切り替える）。
///
/// [SoundVolumeDialog]と同じく、開いた時点の値を`ref.read`で渡すだけの
/// 呼び出し側に対して、スライダーの見た目はこのWidget自身が
/// `StatefulWidget`として持つローカルコピーで反映する。
class CmtSoundVolumeDialog extends StatefulWidget {
  const CmtSoundVolumeDialog({
    super.key,
    required this.l10n,
    required this.settings,
    required this.onChanged,
  });

  final AppLocalizations l10n;
  final CmtSoundSettings settings;
  final void Function(CmtSoundKind kind, double volume) onChanged;

  @override
  State<CmtSoundVolumeDialog> createState() => _CmtSoundVolumeDialogState();
}

class _CmtSoundVolumeDialogState extends State<CmtSoundVolumeDialog> {
  late CmtSoundSettings _settings = widget.settings;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.l10n.cmtSoundVolumeDialogTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _slider(context, CmtSoundKind.noise),
            _slider(context, CmtSoundKind.signal),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('cmtSoundVolumeDialogClose'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.l10n.settingsClose),
        ),
      ],
    );
  }

  Widget _slider(BuildContext context, CmtSoundKind kind) {
    final volume = kind == CmtSoundKind.noise
        ? _settings.noiseVolume
        : _settings.signalVolume;
    final percentage = '${(volume * 100).round()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(_labelOf(kind), style: Theme.of(context).textTheme.labelLarge),
            Text(percentage, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        Slider(
          value: volume,
          onChanged: (value) {
            setState(() {
              _settings = kind == CmtSoundKind.noise
                  ? _settings.copyWith(noiseVolume: value)
                  : _settings.copyWith(signalVolume: value);
            });
            widget.onChanged(kind, value);
          },
        ),
      ],
    );
  }

  String _labelOf(CmtSoundKind kind) {
    final l10n = widget.l10n;
    return switch (kind) {
      CmtSoundKind.noise => l10n.cmtSoundNoise,
      CmtSoundKind.signal => l10n.cmtSoundSignal,
      CmtSoundKind.voice => l10n.cmtSoundVoice,
    };
  }
}
