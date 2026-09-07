import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app/l10n/generated/app_localizations.dart';
import '../../emulator/state_slot_info.dart';
import '../display/screenshot_service.dart';
import '../session/session_providers.dart';

/// [StateSlotDialog]がSave/Loadのどちらとして開かれたか。
enum StateSlotDialogMode { save, load }

/// 状態スロット（0〜9、STA-01/STA-02）のグリッドダイアログ。
///
/// `~/dev/_Emu/Bubilator88`の`SaveStateSheetView`/`SlotCell`
/// （グリッド、サムネイル、保存日時、ディスク名オーバーレイ、Save/Load
/// 共通の1枚のシート、Loadモードでの空スロット無効化）を参考にした
/// 独自実装。Bubilator88自身の`.b88s`コンテナ形式は使わない（本アプリは
/// upstreamコアのopaqueな`.sta`形式をそのまま保存する、design.md
/// 「状態保存（M3、STA-01/STA-02）の実装方式」参照）。スロット番号は
/// specification.mdが定める0〜9をそのまま表示する（Bubilator88は1〜10
/// 表示だが、本製品の仕様を優先する）。
///
/// セルタップで確認を挟まず即座に保存/読込みを確定してダイアログを閉じる
/// （既存の他機能と同じ、単発実行の粒度）。
class StateSlotDialog extends ConsumerStatefulWidget {
  const StateSlotDialog({required this.mode, super.key});

  final StateSlotDialogMode mode;

  @override
  ConsumerState<StateSlotDialog> createState() => _StateSlotDialogState();
}

class _StateSlotDialogState extends ConsumerState<StateSlotDialog> {
  late Future<List<StateSlotInfo>> _future;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _future = ref.read(emulatorControllerProvider.notifier).listStateSlots();
  }

  Future<void> _handleTap(int slot, bool hasData) async {
    if (_busy) {
      return;
    }
    if (widget.mode == StateSlotDialogMode.load && !hasData) {
      return;
    }
    setState(() => _busy = true);
    final controller = ref.read(emulatorControllerProvider.notifier);
    if (widget.mode == StateSlotDialogMode.save) {
      Uint8List? thumbnailBytes;
      try {
        final key = ref.read(screenshotBoundaryKeyProvider);
        final service = ref.read(screenshotServiceProvider);
        thumbnailBytes = await service.captureBytes(key);
      } on ScreenshotException {
        thumbnailBytes = null;
      }
      await controller.saveState(slot, thumbnailBytes: thumbnailBytes);
    } else {
      await controller.loadState(slot);
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isSave = widget.mode == StateSlotDialogMode.save;

    return AlertDialog(
      title: Text(
        isSave ? l10n.stateSlotDialogTitleSave : l10n.stateSlotDialogTitleLoad,
      ),
      content: SizedBox(
        width: 560,
        height: 420,
        child: FutureBuilder<List<StateSlotInfo>>(
          future: _future,
          builder: (context, snapshot) {
            final slots = snapshot.data;
            if (slots == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return GridView.builder(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 220,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
              ),
              itemCount: slots.length,
              itemBuilder: (context, index) {
                final info = slots[index];
                final enabled = !_busy && (isSave || info.hasData);
                return _StateSlotCell(
                  key: Key('stateSlotCell_${info.slot}'),
                  info: info,
                  enabled: enabled,
                  emptyLabel: l10n.stateSlotEmpty,
                  onTap: () => _handleTap(info.slot, info.hasData),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          key: const Key('stateSlotDialogCancel'),
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.stateSlotDialogCancel),
        ),
      ],
    );
  }
}

class _StateSlotCell extends StatelessWidget {
  const _StateSlotCell({
    required this.info,
    required this.enabled,
    required this.emptyLabel,
    required this.onTap,
    super.key,
  });

  final StateSlotInfo info;
  final bool enabled;
  final String emptyLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumbnail = info.thumbnailBytes;
    return Opacity(
      opacity: enabled ? 1.0 : 0.4,
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (thumbnail != null)
                Image.memory(thumbnail, fit: BoxFit.cover)
              else
                Center(
                  child: Text(
                    emptyLabel,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: 0.5,
                      ),
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.bottomLeft,
                child: Container(
                  width: double.infinity,
                  color: Colors.black.withValues(alpha: 0.55),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Slot ${info.slot}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      if (info.savedAt != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          DateFormat('MM/dd HH:mm').format(info.savedAt!),
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                        ),
                      ],
                      if (info.diskNames.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            info.diskNames.join(', '),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
