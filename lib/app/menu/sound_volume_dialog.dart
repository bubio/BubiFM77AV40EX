import 'package:flutter/material.dart';

import '../../emulator/session_state.dart';
import '../l10n/generated/app_localizations.dart';

/// `Device > Sound > Volume…`が開く音量ダイアログ（specification.md
/// AUD-03）。
///
/// 標準OPNのFM・PSG、Beep、キーボード音、FDD機構音の5チャンネルを
/// 個別に調整する。`Application > Settings…`のマスター音量
/// （[SettingsDialog]）とは別物で、コアのゲスト側デバイスそのものの
/// 音量つまみである（design.md「標準音声設定（M3、AUD-03）の実装方式」）。
///
/// 開いた時点の値を`ref.read`で渡すだけの呼び出し側（design.md 12.3、
/// マスター音量ダイアログと同じ制約）に対して、スライダーの見た目は
/// このWidget自身が`StatefulWidget`として持つローカルコピーで反映する
/// （渡すたびに再構築されない`showDialog`のルートでも、5本のうち1本を
/// 動かした結果が他のスライダーへ反映されないよう、ローカルの
/// `SoundChannelVolumes`を単一の情報源にする）。
class SoundVolumeDialog extends StatefulWidget {
  const SoundVolumeDialog({
    super.key,
    required this.l10n,
    required this.volumes,
    required this.onChanged,
  });

  final AppLocalizations l10n;
  final SoundChannelVolumes volumes;
  final void Function(SoundChannel channel, double volume) onChanged;

  @override
  State<SoundVolumeDialog> createState() => _SoundVolumeDialogState();
}

class _SoundVolumeDialogState extends State<SoundVolumeDialog> {
  late SoundChannelVolumes _volumes = widget.volumes;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.l10n.deviceSoundVolume),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final channel in SoundChannel.values) _slider(context, channel),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('soundVolumeDialogClose'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.l10n.settingsClose),
        ),
      ],
    );
  }

  Widget _slider(BuildContext context, SoundChannel channel) {
    final volume = _volumes[channel];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_labelOf(channel), style: Theme.of(context).textTheme.labelLarge),
        Slider(
          value: volume,
          onChanged: (value) {
            setState(() => _volumes = _volumes.withVolume(channel, value));
            widget.onChanged(channel, value);
          },
          label: '${(volume * 100).round()}%',
        ),
      ],
    );
  }

  String _labelOf(SoundChannel channel) {
    final l10n = widget.l10n;
    return switch (channel) {
      SoundChannel.opnFm => l10n.soundChannelOpnFm,
      SoundChannel.opnPsg => l10n.soundChannelOpnPsg,
      SoundChannel.beep => l10n.soundChannelBeep,
      SoundChannel.keyboardBeep => l10n.soundChannelKeyboardBeep,
      SoundChannel.fddMechanism => l10n.soundChannelFddMechanism,
    };
  }
}
