import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../emulator/led_state.dart';
import '../../../emulator/session_state.dart';
import '../../display/screen_fit.dart';
import '../../display/widgets/emulator_screen.dart';
import '../session_providers.dart';

/// エミュレーター画面と、最小限の操作。
///
/// ステータスバーと本格的なメニューはWP6で追加する。
class EmulatorView extends ConsumerWidget {
  const EmulatorView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(emulatorControllerProvider);
    final controller = ref.read(emulatorControllerProvider.notifier);
    final textureId = state.textureId;

    return Focus(
      autofocus: true,
      onFocusChange: (hasFocus) {
        if (!hasFocus) {
          // フォーカス喪失時の全解放（design.md 8）。離す操作を見せないまま
          // ウィンドウを切り替えると、コア側でキーが押されっぱなしになる。
          controller.releaseAllKeys();
        }
      },
      onKeyEvent: (node, event) {
        switch (event) {
          case KeyDownEvent() || KeyRepeatEvent():
            controller.handleKeyDown(
              event.physicalKey,
              logicalKey: event.logicalKey,
            );
          case KeyUpEvent():
            controller.handleKeyUp(
              event.physicalKey,
              logicalKey: event.logicalKey,
            );
        }
        return KeyEventResult.handled;
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Column(
          children: [
            Expanded(
              child: textureId == null
                  ? Center(
                      child: Text(
                        state.session == SessionState.starting
                            ? l10n.emulatorStarting
                            : l10n.emulatorFailed,
                        style: const TextStyle(color: Colors.white),
                      ),
                    )
                  : EmulatorScreen(
                      key: const Key('emulatorScreen'),
                      textureId: textureId,
                      frameWidth: state.frameWidth,
                      frameHeight: state.frameHeight,
                      fit: state.fit,
                    ),
            ),
            Material(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Text(l10n.displayFit),
                    const SizedBox(width: 8),
                    SegmentedButton<ScreenFit>(
                      segments: [
                        ButtonSegment(
                          value: ScreenFit.aspect,
                          label: Text(l10n.displayFitAspect),
                        ),
                        ButtonSegment(
                          value: ScreenFit.integer,
                          label: Text(l10n.displayFitInteger),
                        ),
                        ButtonSegment(
                          value: ScreenFit.fill,
                          label: Text(l10n.displayFitFill),
                        ),
                      ],
                      selected: {state.fit},
                      onSelectionChanged: (selected) =>
                          controller.setFit(selected.first),
                    ),
                    const Spacer(),
                    _LedIndicators(state: state.ledState, l10n: l10n),
                    const SizedBox(width: 12),
                    TextButton(
                      key: const Key('emulatorReset'),
                      onPressed: state.isRunning
                          ? () => controller.reset(ResetKind.normal)
                          : null,
                      child: Text(l10n.emulatorReset),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      key: const Key('emulatorStop'),
                      onPressed: controller.shutdown,
                      child: Text(l10n.emulatorStop),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// INS、KANA、CAPSの意味づけ済み状態を出す（INP-02）。
class _LedIndicators extends StatelessWidget {
  const _LedIndicators({required this.state, required this.l10n});

  final LedState state;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _LedChip(label: l10n.ledInsert, lit: state.insert),
        const SizedBox(width: 6),
        _LedChip(label: l10n.ledKana, lit: state.kana),
        const SizedBox(width: 6),
        _LedChip(label: l10n.ledCaps, lit: state.caps),
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
