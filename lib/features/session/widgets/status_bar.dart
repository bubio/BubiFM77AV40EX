import 'dart:async';

import 'package:flutter/material.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../emulator/session_state.dart';
import '../emulator_state.dart';

/// エミュレーターの一段ステータスバー（design.md 12.4）。
///
/// `BubiC-8801MAのdraw_status_bar()`を構成基準とし、高さ24論理px、
/// 暗色背景、一段表示にする。左からFD2、FD1のアクセスランプ、CMT走行状態
/// （specification.md CMT-05、M4）、マスター音量、INS、KANA、CAPSを置き、
/// 右端へ`[BASIC|DOS]`とView/Core FPSを右寄せする。CPU速度
/// （`2.0MHz|1.2MHz`）はコアから読める観測値がなく、bridgeコマンドも
/// 予約のみ（M3）のため出さない（design.md 16.1）。マウス接続アイコン
/// （P2、INP-06）は本マイルストーンの対象外のまま追加しない。
/// [StatusBar]の高さ（論理px、design.md 12.4）。ウィンドウ倍率計算
/// （`WindowScaleController`）が内容領域からこの分を差し引く。
const double statusBarHeight = 24;

class StatusBar extends StatelessWidget {
  const StatusBar({
    super.key,
    required this.state,
    required this.l10n,
    required this.masterVolume,
  });

  final EmulatorViewState state;
  final AppLocalizations l10n;

  /// 0.0〜1.0（design.md 12.4）。
  final double masterVolume;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Container(
      height: statusBarHeight,
      color: theme.colorScheme.surfaceContainerHighest,
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
          const SizedBox(width: 10),
          Flexible(
            flex: 8,
            child: _CmtIndicator(
              text: l10n.statusCmt(shortenCmtMessage(state.cmtMessage)),
              running: state.cmtPlaying || state.cmtRecording,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            l10n.statusMasterVolume((masterVolume * 100).round()),
            style: textStyle,
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
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AccessLamp(lastAccessed: lastAccessed),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// コアのCMT状態文字列のうち、テープ端での停止を示す長い表記を
/// 走行位置の表記（`Stop (NN %)`）にそろえる。
///
/// upstream `DATAREC::update_event`はテープ端で停止すると
/// `Stop (Beginning-of-Tape)`/`Stop (End-of-Tape)`を返すが、それ以外の
/// 停止位置は`Stop (NN %)`で表すため、端も`0 %`/`100 %`で表示する。
/// upstreamコアは変更できないため、表示の直前でここが置き換える。
String shortenCmtMessage(String message) => switch (message) {
  'Stop (Beginning-of-Tape)' => 'Stop (0 %)',
  'Stop (End-of-Tape)' => 'Stop (100 %)',
  _ => message,
};

/// CMT走行状態の表示（specification.md CMT-05、design.md 12.4、M4）。
///
/// 原作Windows版のステータスバーと同様に「CMT : Play (3 %)」のように
/// 状態と走行位置を1つの文字列で表示する。[text]は
/// [EmulatorSession.getCmtStatus]の`message`（コアの
/// `DATAREC::update_event`/`event_callback`が生成する状態文字列、
/// native/core/upstream/src/vm/datarec.cpp）をそのまま使う。
///
/// FDDのアクセスランプ（read-and-clearの一過性通知）とは性質が異なり、
/// `playing`/`recording`は走行中ずっとtrueであり続ける継続的な状態のため、
/// [AccessLamp]のような自前のタイムアウトは持たず、値をそのまま表示する。
class _CmtIndicator extends StatelessWidget {
  const _CmtIndicator({required this.text, required this.running});

  final String text;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(
          Icons.circle,
          size: 8,
          color: running ? Colors.red : theme.disabledColor,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
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
        color: lit ? theme.colorScheme.primary : theme.disabledColor,
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
    // FDDアクセスランプは実機同様、テーマに関わらず赤固定にする。
    return Icon(
      Icons.circle,
      size: 8,
      color: _isLit ? Colors.red : Theme.of(context).disabledColor,
    );
  }
}
