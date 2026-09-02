import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n/generated/app_localizations.dart';

/// macOS標準Applicationメニュー（design.md 12.1、12.3）。
///
/// About、Services、Hide系はOS標準の`PlatformProvidedMenuItem`で足りる。
/// SettingsとQuitは共通コマンドへ接続する必要があるため、通常の
/// `PlatformMenuItem`にする。Quitは即時終了APIを直接呼ばず、
/// [onQuit]が通常のセッション停止・保存・資源解放を終えてから
/// プロセスを終える（design.md 12.3）。
class PlatformApplicationMenu extends StatelessWidget {
  const PlatformApplicationMenu({
    super.key,
    required this.child,
    required this.l10n,
    required this.onSettings,
    required this.onQuit,
  });

  final Widget child;
  final AppLocalizations l10n;
  final VoidCallback onSettings;
  final Future<void> Function() onQuit;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isMacOS) {
      return child;
    }
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: l10n.appTitle,
          menus: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: l10n.menuAppSettings,
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.comma,
                    meta: true,
                  ),
                  onSelected: onSettings,
                ),
              ],
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.servicesSubmenu,
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hide,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.hideOtherApplications,
                ),
                PlatformProvidedMenuItem(
                  type: PlatformProvidedMenuItemType.showAllApplications,
                ),
              ],
            ),
            PlatformMenuItemGroup(
              members: [
                PlatformMenuItem(
                  label: l10n.menuAppQuit,
                  shortcut: const SingleActivator(
                    LogicalKeyboardKey.keyQ,
                    meta: true,
                  ),
                  onSelected: () {
                    onQuit();
                  },
                ),
              ],
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}
