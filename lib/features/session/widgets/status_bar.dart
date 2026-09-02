import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../emulator/session_state.dart';
import '../emulator_state.dart';

/// エミュレーターの一段ステータスバー（design.md 12.4）。
///
/// `BubiC-8801MAのdraw_status_bar()`を構成基準とし、高さ24論理px、
/// 暗色背景、一段表示にする。左からFD2、FD1のアクセスランプ、INS、
/// KANA、CAPSを置き、右端へ`[BASIC|DOS]`とView/Core FPSを右寄せする。
/// マスター音量とCPU速度（`2.0MHz|1.2MHz`）はホスト側にその機能自体が
/// まだないため出さない（design.md 12.4のP0対象のうち、音量調整と
/// CPU速度切替は別途実装が要る）。
class StatusBar extends StatelessWidget {
  const StatusBar({super.key, required this.state, required this.l10n});

  final EmulatorViewState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.labelSmall
        ?.copyWith(color: Colors.white70);
    return Container(
      height: 24,
      color: const Color(0xFF1A1A1A),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          _FddLamp(
            label: l10n.fddDriveLabel(2),
            lastAccessed: state.fddLastAccessed[1],
          ),
          const SizedBox(width: 10),
          _FddLamp(
            label: l10n.fddDriveLabel(1),
            lastAccessed: state.fddLastAccessed[0],
          ),
          const SizedBox(width: 14),
          _LedChip(label: l10n.ledInsert, lit: state.ledState.insert),
          const SizedBox(width: 6),
          _LedChip(label: l10n.ledKana, lit: state.ledState.kana),
          const SizedBox(width: 6),
          _LedChip(label: l10n.ledCaps, lit: state.ledState.caps),
          const Spacer(),
          Text(
            state.bootMode == BootMode.basic
                ? l10n.romBootModeBasic
                : l10n.romBootModeDos,
            style: textStyle,
          ),
          const SizedBox(width: 10),
          Text(l10n.statusViewFps(state.viewFps.round()), style: textStyle),
          const SizedBox(width: 10),
          Text(l10n.statusCoreFps(state.coreFps.round()), style: textStyle),
        ],
      ),
    );
  }
}

class _FddLamp extends StatelessWidget {
  const _FddLamp({required this.label, required this.lastAccessed});

  final String label;
  final DateTime? lastAccessed;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AccessLamp(lastAccessed: lastAccessed),
        const SizedBox(width: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall
              ?.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}

class _LedChip extends StatelessWidget {
  const _LedChip({required this.label, required this.lit});

  final String label;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: lit ? theme.colorScheme.primary : Colors.white38,
        fontWeight: lit ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }
}

/// 直近アクセス時刻に対して自前でタイムアウトを持つアクセスランプ。
///
/// ネイティブ側の`FD1/FD2`アクセスフラグはread-and-clearで、呼ぶたびに
/// 消費される（`bfm_get_media_access`）。届くのは「アクセスがあった」
/// という一過性の時刻だけなので、点灯の持続時間はここが自分で決める
/// （design.md 16.1）。
class AccessLamp extends StatefulWidget {
  const AccessLamp({super.key, required this.lastAccessed});

  final DateTime? lastAccessed;

  @override
  State<AccessLamp> createState() => _AccessLampState();
}

class _AccessLampState extends State<AccessLamp> {
  static const _duration = Duration(milliseconds: 300);

  Timer? _timer;

  @override
  void didUpdateWidget(covariant AccessLamp oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.lastAccessed != null &&
        widget.lastAccessed != oldWidget.lastAccessed) {
      _timer?.cancel();
      _timer = Timer(_duration, () {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  bool get _isLit {
    final lastAccessed = widget.lastAccessed;
    if (lastAccessed == null) {
      return false;
    }
    return DateTime.now().difference(lastAccessed) < _duration;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Icon(
      Icons.circle,
      size: 8,
      color: _isLit ? theme.colorScheme.primary : theme.disabledColor,
    );
  }
}
