import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/generated/app_localizations.dart';
import 'joystick_assignment_controller.dart';

/// `Device > Joystick…`が開く割当ダイアログ（M3 INP-04）。
///
/// JS1/JS2それぞれに、接続中の物理コントローラーをドロップダウンで
/// 割り当てる。方向・ボタンの割当自体は固定（INP-05のスコープ外）。
/// 接続一覧は`gamepads`パッケージに接続/切断の専用通知が無いため、
/// このダイアログを開いている間だけポーリングして更新する（design.md
/// 「ジョイスティック割当（M3、INP-04）の実装方式」）。
class JoystickAssignmentDialog extends ConsumerStatefulWidget {
  const JoystickAssignmentDialog({super.key});

  static const _slots = [0, 1];

  @override
  ConsumerState<JoystickAssignmentDialog> createState() =>
      _JoystickAssignmentDialogState();
}

class _JoystickAssignmentDialogState
    extends ConsumerState<JoystickAssignmentDialog> {
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    final notifier = ref.read(joystickAssignmentControllerProvider.notifier);
    unawaited(notifier.refreshConnected());
    _pollTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(notifier.refreshConnected());
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final joystick = ref.watch(joystickAssignmentControllerProvider);
    final notifier = ref.read(joystickAssignmentControllerProvider.notifier);

    return AlertDialog(
      title: Text(l10n.deviceJoystick),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final slot in JoystickAssignmentDialog._slots)
            _slotRow(context, l10n, joystick, notifier, slot),
        ],
      ),
      actions: [
        TextButton(
          key: const Key('joystickAssignmentDialogClose'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.settingsClose),
        ),
      ],
    );
  }

  Widget _slotRow(
    BuildContext context,
    AppLocalizations l10n,
    JoystickAssignmentState joystick,
    JoystickAssignmentController notifier,
    int slot,
  ) {
    final assigned = joystick.assignments[slot];
    final connectedIds = joystick.connected.map((info) => info.id).toSet();
    // 切断済みでも、割当自体は次の接続一覧更新まで表示上残さない。
    final currentValue = connectedIds.contains(assigned) ? assigned : null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          SizedBox(
            width: 96,
            child: Text(
              slot == 0 ? l10n.deviceJoystickSlot1 : l10n.deviceJoystickSlot2,
            ),
          ),
          Expanded(
            child: DropdownButton<String?>(
              key: Key('joystickAssignmentDialogSlot$slot'),
              isExpanded: true,
              value: currentValue,
              hint: Text(l10n.deviceJoystickUnassigned),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(l10n.deviceJoystickUnassigned),
                ),
                for (final info in joystick.connected)
                  DropdownMenuItem<String?>(
                    value: info.id,
                    child: Text(info.name),
                  ),
              ],
              onChanged: (value) => notifier.assign(slot, value),
            ),
          ),
        ],
      ),
    );
  }
}
