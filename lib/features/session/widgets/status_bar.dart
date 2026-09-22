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
    required this.onMasterVolumeChanged,
  });

  final EmulatorViewState state;
  final AppLocalizations l10n;

  /// 0.0〜1.0（design.md 12.4）。
  final double masterVolume;

  /// ステータスバーのスライダーでマスター音量を変えたときに呼ぶ。
  final ValueChanged<double> onMasterVolumeChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    // 毎秒変わるFPSやCMTの走行位置は、数字ごとの字幅差で位置が揺れないよう
    // 等幅数字にする。
    final fpsStyle = textStyle?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      height: statusBarHeight,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          // 左側のまとまりが残りの幅をすべて受け持ち、幅が足りないときは
          // CMT表示だけが縮む。余った幅はまとまりの右側に空くため、
          // 右側の起動モードとFPSは常にステータスバーの右端へ寄る。
          Expanded(
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
                  child: _CmtIndicator(
                    message: state.cmtMessage,
                    fullText: l10n.statusCmt(
                      shortenCmtMessage(state.cmtMessage),
                    ),
                    running: state.cmtPlaying || state.cmtRecording,
                    textStyle: fpsStyle,
                  ),
                ),
                const SizedBox(width: 10),
                _VolumeControl(
                  volume: masterVolume,
                  semanticsLabel: l10n.statusMasterVolume(
                    (masterVolume * 100).round(),
                  ),
                  onChanged: onMasterVolumeChanged,
                ),
                const SizedBox(width: 14),
                _LedChip(label: l10n.ledInsert, lit: state.ledState.insert),
                const SizedBox(width: 6),
                _LedChip(label: l10n.ledKana, lit: state.ledState.kana),
                const SizedBox(width: 6),
                _LedChip(label: l10n.ledCaps, lit: state.ledState.caps),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            state.bootMode == BootMode.basic
                ? l10n.romBootModeBasic
                : l10n.romBootModeDos,
            style: textStyle,
          ),
          const SizedBox(width: 10),
          GrowOnlyText(
            l10n.statusViewFps(state.viewFps.round()),
            style: fpsStyle,
          ),
          const SizedBox(width: 10),
          GrowOnlyText(
            l10n.statusCoreFps(state.coreFps.round()),
            style: fpsStyle,
          ),
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

/// CMTの走行状態（upstream `DATAREC`の状態文字列の種類）。
enum CmtTransport { stop, play, record, fastForward, fastRewind }

/// コアのCMT状態文字列を走行状態と走行位置（%）に分ける。
///
/// upstream `DATAREC::update_event`/`event_callback`
/// （native/core/upstream/src/vm/datarec.cpp）が生成する
/// `Play (NN %)`/`Stop (NN %)`/`Stop`/`Record`/`Fast Forward (NN %)`/
/// `Fast Rewind (NN %)`を対象にし、テープ端の停止は[shortenCmtMessage]で
/// `0 %`/`100 %`へそろえてから解釈する。未知の文字列はnullを返す。
({CmtTransport transport, int? percent})? parseCmtMessage(String message) {
  final match = _cmtMessagePattern.firstMatch(shortenCmtMessage(message));
  if (match == null) return null;
  final transport = switch (match.group(1)!) {
    'Play' => CmtTransport.play,
    'Record' => CmtTransport.record,
    'Fast Forward' => CmtTransport.fastForward,
    'Fast Rewind' => CmtTransport.fastRewind,
    _ => CmtTransport.stop,
  };
  final percent = match.group(2);
  return (
    transport: transport,
    percent: percent == null ? null : int.parse(percent),
  );
}

final _cmtMessagePattern = RegExp(
  r'^(Play|Stop|Record|Fast Forward|Fast Rewind)(?: \((\d+) %\))?$',
);

/// CMT走行状態の表示（specification.md CMT-05、design.md 12.4、M4）。
///
/// ステータスバーの幅を節約するため、「CMT ▶ 3 %」のように走行状態を
/// アイコンで、走行位置を数字で示す。状態文字列の全文（原作Windows版の
/// 「CMT : Play (3 %)」）はツールチップと読み上げに残す。[message]は
/// [EmulatorSession.getCmtStatus]の`message`をそのまま受け取り、解釈
/// できない文字列ならアイコンにせず全文を表示する。
///
/// FDDのアクセスランプ（read-and-clearの一過性通知）とは性質が異なり、
/// `playing`/`recording`は走行中ずっとtrueであり続ける継続的な状態のため、
/// [AccessLamp]のような自前のタイムアウトは持たず、値をそのまま表示する。
class _CmtIndicator extends StatelessWidget {
  const _CmtIndicator({
    required this.message,
    required this.fullText,
    required this.running,
    required this.textStyle,
  });

  final String message;
  final String fullText;
  final bool running;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final parsed = parseCmtMessage(message);
    final color = running ? Colors.red : theme.colorScheme.onSurfaceVariant;
    final Widget content;
    if (parsed == null) {
      content = Text(
        fullText,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
        style: textStyle,
      );
    } else {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('CMT', style: textStyle),
          const SizedBox(width: 4),
          Icon(
            switch (parsed.transport) {
              CmtTransport.stop => Icons.stop,
              CmtTransport.play => Icons.play_arrow,
              CmtTransport.record => Icons.fiber_manual_record,
              CmtTransport.fastForward => Icons.fast_forward,
              CmtTransport.fastRewind => Icons.fast_rewind,
            },
            size: 14,
            color: color,
          ),
          if (parsed.percent case final percent?) ...[
            const SizedBox(width: 2),
            // 桁数が変わっても後ろの音量スライダーが動かないよう、
            // 3桁（100 %）の幅を常に確保して右寄せにする。
            Stack(
              alignment: Alignment.centerRight,
              children: [
                Opacity(opacity: 0, child: Text('100 %', style: textStyle)),
                Text('$percent %', style: textStyle),
              ],
            ),
          ],
        ],
      );
    }
    return Tooltip(
      message: fullText,
      excludeFromSemantics: true,
      child: Semantics(label: fullText, excludeSemantics: true, child: content),
    );
  }
}

/// 表示幅をこれまでの最大幅より縮めない右寄せテキスト。
///
/// 右寄せ行の末尾にある値（FPSなど）の桁数が一時的に減ると、行全体が
/// 左右に揺れる。固定幅を決め打ちせず、実際に表示した最大幅だけを
/// 保持して桁の増減による位置ずれを抑える。
class GrowOnlyText extends StatefulWidget {
  const GrowOnlyText(this.text, {super.key, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<GrowOnlyText> createState() => _GrowOnlyTextState();
}

class _GrowOnlyTextState extends State<GrowOnlyText> {
  double _maxWidth = 0;

  @override
  Widget build(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: widget.text,
        style: DefaultTextStyle.of(context).style.merge(widget.style),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    if (width > _maxWidth) {
      _maxWidth = width;
    }
    return SizedBox(
      width: _maxWidth,
      child: Text(
        widget.text,
        style: widget.style,
        textAlign: TextAlign.right,
        maxLines: 1,
        softWrap: false,
      ),
    );
  }
}

/// マスター音量のスライダー（design.md 12.4）。
///
/// 音量はSoLoudのグローバル音量としてかかり、コアPCMとFDD機構音の
/// 両方を含むアプリ全体の出力に効く。高さ[statusBarHeight]に収まるよう、
/// トラックとつまみを小さくしてoverlayを出さない。
class _VolumeControl extends StatelessWidget {
  const _VolumeControl({
    required this.volume,
    required this.semanticsLabel,
    required this.onChanged,
  });

  final double volume;
  final String semanticsLabel;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          volume == 0 ? Icons.volume_off : Icons.volume_up,
          size: 14,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        SizedBox(
          width: 68,
          height: statusBarHeight,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              key: const Key('statusMasterVolumeSlider'),
              value: volume,
              onChanged: onChanged,
              semanticFormatterCallback: (_) => semanticsLabel,
            ),
          ),
        ),
      ],
    );
  }
}

/// INS/KANA/CAPSのLED表示。
///
/// 点灯中は太字にするが、太字と通常とで字幅が違うため、見えない太字の
/// ラベルを重ねて常に太字の幅を確保し、点灯の切り替えで周囲を動かさない。
class _LedChip extends StatelessWidget {
  const _LedChip({required this.label, required this.lit});

  final String label;
  final bool lit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall;
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: 0,
          child: Text(
            label,
            style: style?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Text(
          label,
          style: style?.copyWith(
            color: lit ? theme.colorScheme.primary : theme.disabledColor,
            fontWeight: lit ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
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
