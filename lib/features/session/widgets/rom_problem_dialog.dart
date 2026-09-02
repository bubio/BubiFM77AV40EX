import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../emulator/rom/rom_inventory.dart';
import '../../../emulator/rom/rom_requirement.dart';
import '../../../emulator/rom/rom_status.dart';
import '../../../emulator/session_state.dart';
import '../session_providers.dart';

/// 起動必須ROMに異常があるとき、または走査自体が失敗したときに出す
/// ダイアログ（APP-06: 対象・原因・対応を表示する）。
///
/// `decideRomBootAction`（`rom_boot_decision.dart`）が`showProblem`を
/// 返した場合だけ、呼び出し側（`app.dart`の`_Home`）が開く。表示対象は
/// 起動必須6ファイル（`RomRole.bootRequired`）の異常だけであり、
/// F-BASIC ROM（`RomRole.basicRequired`）の欠落はここに出さない
/// （design.md 301、`rom_boot_decision.dart`のコメントを参照）。
///
/// Boot Modeの選択はここへ置かない。`Control > Boot mode`メニューに
/// 既にある（design.md 12.2）。
class RomProblemDialog extends ConsumerWidget {
  const RomProblemDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(romSettingsControllerProvider);
    final controller = ref.read(romSettingsControllerProvider.notifier);

    // 再検証で起動必須ROMが揃い、`_Home`が自動的に起動を始めたら、
    // このダイアログは役目を終える。開いたままだと、起動した
    // エミュレーター画面を覆い続けてしまう。
    ref.listen(emulatorControllerProvider, (previous, next) {
      if (next.session != SessionState.stopped) {
        Navigator.of(context).maybePop();
      }
    });

    return AlertDialog(
      title: Text(l10n.romProblemTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (state.scanFailed)
              Text(l10n.romScanFailed)
            else ...[
              Text(l10n.romNotReady),
              const SizedBox(height: 8),
              for (final entry in state.inventory?.bootBlockingProblems ?? [])
                _EntryRow(
                  entry: entry,
                  key: Key('romEntry_${entry.requirement.id}'),
                ),
            ],
            const SizedBox(height: 12),
            Text(l10n.romDirectoryLabel, style: _labelStyle(context)),
            const SizedBox(height: 4),
            Text(
              state.romsDirectoryPath ?? l10n.romDirectoryPreparing,
              key: const Key('romDirectoryPath'),
              style: _captionStyle(context),
            ),
            const SizedBox(height: 4),
            Text(l10n.romDirectoryGuidance),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: state.hasDirectory ? controller.revealRomsDirectory : null,
          child: Text(l10n.romOpenFolder),
        ),
        FilledButton(
          onPressed: state.isScanning ? null : controller.rescan,
          child: Text(state.isScanning ? l10n.romScanning : l10n.romRescan),
        ),
        TextButton(
          key: const Key('romProblemDialogClose'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.settingsClose),
        ),
      ],
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, super.key});

  final RomInventoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(entry.fileName ?? entry.requirement.primaryFileName),
          ),
          Text(
            _roleLabel(l10n, entry.requirement.role),
            style: _captionStyle(context),
          ),
          const SizedBox(width: 12),
          Text(
            _statusLabel(l10n, entry.status),
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ],
      ),
    );
  }
}

TextStyle? _labelStyle(BuildContext context) =>
    Theme.of(context).textTheme.titleSmall;

TextStyle? _captionStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall;

String _roleLabel(AppLocalizations l10n, RomRole role) => switch (role) {
  RomRole.bootRequired => l10n.romRoleBootRequired,
  RomRole.basicRequired => l10n.romRoleBasicRequired,
  RomRole.optional => l10n.romRoleOptional,
};

String _statusLabel(AppLocalizations l10n, RomStatus status) =>
    switch (status) {
      RomStatus.missing => l10n.romStatusMissing,
      RomStatus.unreadable => l10n.romStatusUnreadable,
      RomStatus.wrongSize => l10n.romStatusWrongSize,
      RomStatus.hashMismatch => l10n.romStatusHashMismatch,
      RomStatus.verified => l10n.romStatusVerified,
      RomStatus.sizeOnly => l10n.romStatusSizeOnly,
    };
