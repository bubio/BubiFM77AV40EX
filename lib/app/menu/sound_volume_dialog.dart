import 'package:flutter/material.dart';

import '../../emulator/session_state.dart';
import '../l10n/generated/app_localizations.dart';

/// `Host > Sound > Volume…`が開く音量ダイアログ（specification.md
/// AUD-03、AUD-07統合）。
///
/// 標準OPNのFM・PSG、Beep、キーボード音、FDD機構音の5チャンネルと、
/// CMTノイズ・CMT信号の2チャンネルを「CMT」セクションとして続けて表示する。
/// `Application > Settings…`のマスター音量（[SettingsDialog]）とは別物で、
/// コアのゲスト側デバイスそのものの音量つまみである
/// （design.md「標準音声設定（M3、AUD-03）の実装方式」）。
///
/// 開いた時点の値を`ref.read`で渡すだけの呼び出し側（design.md 12.3、
/// マスター音量ダイアログと同じ制約）に対して、スライダーの見た目は
/// このWidget自身が`StatefulWidget`として持つローカルコピーで反映する
/// （渡すたびに再構築されない`showDialog`のルートでも、各スライダーを
/// 動かした結果が他のスライダーへ反映されないよう、ローカルの
/// 状態を単一の情報源にする）。
class SoundVolumeDialog extends StatefulWidget {
  const SoundVolumeDialog({
    super.key,
    required this.l10n,
    required this.volumes,
    required this.onChanged,
    required this.cmtSettings,
    required this.onCmtChanged,
  });

  final AppLocalizations l10n;
  final SoundChannelVolumes volumes;
  final void Function(SoundChannel channel, double volume) onChanged;
  final CmtSoundSettings cmtSettings;
  final void Function(CmtSoundKind kind, double volume) onCmtChanged;

  @override
  State<SoundVolumeDialog> createState() => _SoundVolumeDialogState();
}

class _SoundVolumeDialogState extends State<SoundVolumeDialog> {
  late SoundChannelVolumes _volumes = widget.volumes;
  late CmtSoundSettings _cmtSettings = widget.cmtSettings;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.l10n.hostSoundVolume),
      content: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final channel in SoundChannel.values)
                _channelSlider(context, channel),
              _cmtSlider(context, CmtSoundKind.noise),
              _cmtSlider(context, CmtSoundKind.signal),
            ],
          ),
        ),
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

  Widget _channelSlider(BuildContext context, SoundChannel channel) {
    final volume = _volumes[channel];
    final percentage = '${(volume * 100).round()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _channelLabel(channel),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text(percentage, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        Slider(
          value: volume,
          onChanged: (value) {
            setState(() => _volumes = _volumes.withVolume(channel, value));
            widget.onChanged(channel, value);
          },
        ),
      ],
    );
  }

  Widget _cmtSlider(BuildContext context, CmtSoundKind kind) {
    final volume = kind == CmtSoundKind.noise
        ? _cmtSettings.noiseVolume
        : _cmtSettings.signalVolume;
    final percentage = '${(volume * 100).round()}%';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _cmtLabel(kind),
              style: Theme.of(context).textTheme.labelLarge,
            ),
            Text(percentage, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
        Slider(
          value: volume,
          onChanged: (value) {
            setState(() {
              _cmtSettings = kind == CmtSoundKind.noise
                  ? _cmtSettings.copyWith(noiseVolume: value)
                  : _cmtSettings.copyWith(signalVolume: value);
            });
            widget.onCmtChanged(kind, value);
          },
        ),
      ],
    );
  }

  String _channelLabel(SoundChannel channel) {
    final l10n = widget.l10n;
    return switch (channel) {
      SoundChannel.opnFm => l10n.soundChannelOpnFm,
      SoundChannel.opnPsg => l10n.soundChannelOpnPsg,
      SoundChannel.beep => l10n.soundChannelBeep,
      SoundChannel.keyboardBeep => l10n.soundChannelKeyboardBeep,
      SoundChannel.fddMechanism => l10n.soundChannelFddMechanism,
    };
  }

  String _cmtLabel(CmtSoundKind kind) {
    final l10n = widget.l10n;
    return switch (kind) {
      CmtSoundKind.noise => l10n.cmtSoundNoise,
      CmtSoundKind.signal => l10n.cmtSoundSignal,
      CmtSoundKind.voice => l10n.cmtSoundVoice,
    };
  }
}
