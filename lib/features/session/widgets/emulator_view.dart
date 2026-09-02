import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/l10n/generated/app_localizations.dart';
import '../../../emulator/session_state.dart';
import '../../display/widgets/emulator_screen.dart';
import '../../settings/settings_controller.dart';
import '../session_providers.dart';
import 'status_bar.dart';

/// エミュレーター画面。
///
/// `Control / Disk / Device / Host`のアプリ内メニュー（design.md 12.1）は
/// `app`（`app.dart`の`_Home`）が[EmulatorView]を包んで組み立てる。
/// featureはplatform実装とappへ依存しない（design.md 3.1）ため、
/// カタログの組み立てはここへ置かない。
class EmulatorView extends ConsumerWidget {
  const EmulatorView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(emulatorControllerProvider);
    final controller = ref.read(emulatorControllerProvider.notifier);
    final settings = ref.watch(settingsControllerProvider);
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
                      child: Text(switch (state.session) {
                        SessionState.starting => l10n.emulatorStarting,
                        SessionState.failed => l10n.emulatorFailed,
                        // stopped/stopping: ROM検証中またはROM問題ダイアログの
                        // 背後に出る状態であり、「起動できませんでした。」は
                        // 誤り（design.md 301、rom_boot_decision.dart）。
                        _ => '',
                      }, style: const TextStyle(color: Colors.white)),
                    )
                  : EmulatorScreen(
                      key: const Key('emulatorScreen'),
                      textureId: textureId,
                      frameWidth: state.frameWidth,
                      frameHeight: state.frameHeight,
                      fit: state.fit,
                    ),
            ),
            StatusBar(
              state: state,
              l10n: l10n,
              masterVolume: settings.masterVolume,
            ),
          ],
        ),
      ),
    );
  }
}
