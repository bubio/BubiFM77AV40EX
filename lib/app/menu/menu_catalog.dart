import '../../emulator/session_state.dart';
import '../../features/display/screen_fit.dart';
import '../../features/settings/settings_state.dart';
import '../l10n/generated/app_localizations.dart';
import 'menu_command.dart';

/// `Control / Disk / Device / Host`カタログを組み立てる（design.md 12.2）。
///
/// design.md 12.2のツリーのうちP0項目だけを対象にする。P1/P2はホスト側に
/// まだ実装がないため、無効項目としては出さずカタログから外す
/// （design.md 12.3「P2項目は対応フェーズまでカタログ上で非表示」を、
/// 未実装のP1項目にも同じ理由で適用する）。P1化はM3の依存順（design.md
/// 8章）で個別に追加する。
///
/// Widgetに依存しない純粋な関数にして、構造をWidgetなしでテストできる
/// ようにする。呼び出し側（アプリ内メニューとmacOS標準Applicationメニュー
/// の両方）はここが返す同じカタログを描画するだけで、別々の状態を
/// 持たない（design.md 12.3）。
List<MenuGroup> buildMenuCatalog({
  required AppLocalizations l10n,
  required bool isRunning,
  required void Function(ResetKind kind) onReset,
  required BootMode bootMode,
  required void Function(BootMode mode) onBootModeChanged,
  required Map<int, String?> fddMedia,
  required void Function(int drive) onFddInsert,
  required void Function(int drive) onFddEject,
  required ScreenFit screenFit,
  required void Function(ScreenFit fit) onScreenFitChanged,
  required AppLocaleMode localeMode,
  required void Function(AppLocaleMode mode) onLocaleModeChanged,
}) {
  return [
    MenuGroup(
      id: MenuGroupId.control,
      label: l10n.menuControl,
      entries: [
        MenuAction(
          'control.reset',
          label: l10n.emulatorReset,
          enabled: isRunning,
          onSelected: () => onReset(ResetKind.normal),
        ),
        MenuAction(
          'control.specialReset',
          label: l10n.menuControlSpecialReset,
          enabled: isRunning,
          onSelected: () => onReset(ResetKind.special),
        ),
        const MenuSeparator('control.sep1'),
        MenuRadioGroup<BootMode>(
          'control.bootMode',
          label: l10n.romBootMode,
          groupValue: bootMode,
          options: [
            MenuRadioOption(
              value: BootMode.basic,
              label: l10n.romBootModeBasic,
            ),
            MenuRadioOption(value: BootMode.dos, label: l10n.romBootModeDos),
          ],
          onChanged: onBootModeChanged,
        ),
      ],
    ),
    MenuGroup(
      id: MenuGroupId.disk,
      label: l10n.menuDisk,
      entries: [
        for (var drive = 0; drive < 2; drive++)
          MenuSubmenu(
            'disk.fd$drive',
            label: l10n.fddDriveLabel(drive + 1),
            entries: [
              MenuAction(
                'disk.fd$drive.insert',
                label: l10n.fddInsert,
                enabled: isRunning && fddMedia[drive] == null,
                onSelected: () => onFddInsert(drive),
              ),
              MenuAction(
                'disk.fd$drive.eject',
                label: l10n.fddEject,
                enabled: isRunning && fddMedia[drive] != null,
                onSelected: () => onFddEject(drive),
              ),
            ],
          ),
      ],
    ),
    MenuGroup(
      id: MenuGroupId.device,
      label: l10n.menuDevice,
      entries: [
        MenuSubmenu(
          'device.sound',
          label: l10n.menuDeviceSound,
          entries: const [
            // OPNしか選べないため、選択済みで無効の単一ラジオとして出す
            // （design.md 12.2の`Sound > OPN [P0]`）。
            MenuRadioGroup<String>(
              'device.sound.chip',
              label: '',
              groupValue: 'opn',
              options: [MenuRadioOption(value: 'opn', label: 'OPN')],
              onChanged: _noopStringChanged,
            ),
          ],
        ),
      ],
    ),
    MenuGroup(
      id: MenuGroupId.host,
      label: l10n.menuHost,
      entries: [
        MenuSubmenu(
          'host.screen',
          label: l10n.menuHostScreen,
          entries: [
            MenuRadioGroup<ScreenFit>(
              'host.screen.fit',
              label: l10n.displayFit,
              groupValue: screenFit,
              options: [
                MenuRadioOption(
                  value: ScreenFit.aspect,
                  label: l10n.displayFitAspect,
                ),
                MenuRadioOption(
                  value: ScreenFit.integer,
                  label: l10n.displayFitInteger,
                ),
                MenuRadioOption(
                  value: ScreenFit.fill,
                  label: l10n.displayFitFill,
                ),
              ],
              onChanged: onScreenFitChanged,
            ),
          ],
        ),
        const MenuSeparator('host.sep1'),
        MenuSubmenu(
          'host.language',
          label: l10n.menuHostLanguage,
          entries: [
            MenuRadioGroup<AppLocaleMode>(
              'host.language.mode',
              label: '',
              groupValue: localeMode,
              options: [
                MenuRadioOption(
                  value: AppLocaleMode.system,
                  label: l10n.menuLanguageSystem,
                ),
                MenuRadioOption(
                  value: AppLocaleMode.english,
                  label: l10n.menuLanguageEnglish,
                ),
                MenuRadioOption(
                  value: AppLocaleMode.japanese,
                  label: l10n.menuLanguageJapanese,
                ),
              ],
              onChanged: onLocaleModeChanged,
            ),
          ],
        ),
      ],
    ),
  ];
}

void _noopStringChanged(String value) {}
