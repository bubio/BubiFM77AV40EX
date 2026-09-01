import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../emulator/rom/rom_inventory.dart';
import '../../../emulator/rom/rom_requirement.dart';
import '../../../emulator/rom/rom_status.dart';
import '../../../emulator/session_state.dart';
import '../rom_settings_controller.dart';
import '../rom_settings_state.dart';
import '../session_providers.dart';

/// ROMの検証結果とブートモードを表示する（WP2、M1退出条件「ROMエラーを表示できる」）。
///
/// 不足ROMはファイル単位で示す。フルパスは表示せず、フォルダー名だけを出す
/// （NFR-07）。エミュレーター画面そのものはM2 WP6で作る。
class RomStatusView extends ConsumerWidget {
  const RomStatusView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(romSettingsControllerProvider);
    final controller = ref.read(romSettingsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.romSettingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _DirectorySection(state: state, controller: controller),
          const SizedBox(height: 16),
          _BootModeSection(state: state, controller: controller),
          const SizedBox(height: 16),
          if (state.inventory != null) _InventorySection(state: state),
        ],
      ),
    );
  }
}

class _DirectorySection extends StatelessWidget {
  const _DirectorySection({required this.state, required this.controller});

  final RomSettingsState state;
  final RomSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.romDirectoryLabel, style: _labelStyle(context)),
            const SizedBox(height: 4),
            // 置き場所は固定なので、案内としてパスをそのまま出す。
            Text(
              state.romsDirectoryPath ?? l10n.romDirectoryPreparing,
              key: const Key('romDirectoryPath'),
              style: _captionStyle(context),
            ),
            const SizedBox(height: 4),
            Text(l10n.romDirectoryGuidance),
            if (state.scanFailed) ...[
              const SizedBox(height: 8),
              Text(
                l10n.romScanFailed,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton(
                  onPressed: state.hasDirectory && !state.isScanning
                      ? () => controller.rescan()
                      : null,
                  child: Text(
                    state.isScanning ? l10n.romScanning : l10n.romRescan,
                  ),
                ),
                OutlinedButton(
                  onPressed: state.hasDirectory
                      ? () => controller.revealRomsDirectory()
                      : null,
                  child: Text(l10n.romOpenFolder),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BootModeSection extends StatelessWidget {
  const _BootModeSection({required this.state, required this.controller});

  final RomSettingsState state;
  final RomSettingsController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.romBootMode, style: _labelStyle(context)),
            const SizedBox(height: 8),
            SegmentedButton<BootMode>(
              segments: [
                ButtonSegment(
                  value: BootMode.basic,
                  label: Text(l10n.romBootModeBasic),
                ),
                ButtonSegment(
                  value: BootMode.dos,
                  label: Text(l10n.romBootModeDos),
                ),
              ],
              selected: {state.bootMode},
              onSelectionChanged: (selection) =>
                  controller.setBootMode(selection.first),
            ),
            const SizedBox(height: 8),
            Text(l10n.romBootModeAppliesOnReset, style: _captionStyle(context)),
          ],
        ),
      ),
    );
  }
}

class _InventorySection extends StatelessWidget {
  const _InventorySection({required this.state});

  final RomSettingsState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inventory = state.inventory!;

    final String summary;
    if (inventory.canBootBasic) {
      summary = l10n.romReadyBasic;
    } else if (inventory.canBootDos) {
      summary = l10n.romReadyDosOnly;
    } else {
      summary = l10n.romNotReady;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(summary, key: const Key('romSummary')),
            if (inventory.hasUnverifiedRoms) ...[
              const SizedBox(height: 4),
              Text(l10n.romUnverified, style: _captionStyle(context)),
            ],
            const Divider(height: 24),
            for (final entry in inventory.entries)
              _EntryRow(
                entry: entry,
                key: Key('romEntry_${entry.requirement.id}'),
              ),
          ],
        ),
      ),
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
    final color = entry.isUsable
        ? theme.colorScheme.onSurface
        : (entry.requirement.role == RomRole.optional
              ? theme.colorScheme.tertiary
              : theme.colorScheme.error);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            // 採用したファイル名。見つからないときは代表名を出す。
            child: Text(entry.fileName ?? entry.requirement.primaryFileName),
          ),
          Text(
            _roleLabel(l10n, entry.requirement.role),
            style: _captionStyle(context),
          ),
          const SizedBox(width: 12),
          Text(
            _statusLabel(l10n, entry.status),
            style: TextStyle(color: color),
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
