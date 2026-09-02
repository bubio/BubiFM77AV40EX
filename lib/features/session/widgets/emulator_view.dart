import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../emulator/session_state.dart';
import '../../display/screen_fit.dart';
import '../../display/widgets/emulator_screen.dart';
import '../emulator_controller.dart';
import '../emulator_state.dart';
import '../session_providers.dart';
import 'status_bar.dart';

/// エミュレーター画面と、最小限の操作。
///
/// 本格的なメニューはWP6で追加する。
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
            StatusBar(state: state, l10n: l10n),
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
                    const SizedBox(width: 16),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: _FddSlots(
                          state: state,
                          controller: controller,
                          l10n: l10n,
                        ),
                      ),
                    ),
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

/// FD1(0)、FD2(1)の挿入・排出を並べる（FDD-01）。
class _FddSlots extends StatelessWidget {
  const _FddSlots({
    required this.state,
    required this.controller,
    required this.l10n,
  });

  final EmulatorViewState state;
  final EmulatorController controller;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var drive = 0; drive < 2; drive++) ...[
          if (drive > 0) const SizedBox(width: 12),
          _FddSlot(
            drive: drive,
            mediaName: state.fddMedia[drive],
            enabled: state.isRunning,
            controller: controller,
            l10n: l10n,
          ),
        ],
      ],
    );
  }
}

/// 1ドライブ分の媒体名表示と挿入・排出ボタン。
///
/// アクセスランプは`StatusBar`（design.md 12.4）が持つため、ここでは
/// 出さない。
class _FddSlot extends StatelessWidget {
  const _FddSlot({
    required this.drive,
    required this.mediaName,
    required this.enabled,
    required this.controller,
    required this.l10n,
  });

  final int drive;
  final String? mediaName;
  final bool enabled;
  final EmulatorController controller;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('${l10n.fddDriveLabel(drive + 1)}: ${mediaName ?? l10n.fddEmpty}'),
        const SizedBox(width: 4),
        TextButton(
          key: Key('fdd${drive}Action'),
          onPressed: !enabled
              ? null
              : mediaName == null
              ? () => controller.insertFdd(drive)
              : () => controller.ejectFdd(drive),
          child: Text(mediaName == null ? l10n.fddInsert : l10n.fddEject),
        ),
      ],
    );
  }
}
