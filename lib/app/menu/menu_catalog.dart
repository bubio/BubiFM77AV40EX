import '../../emulator/session_state.dart';
import '../../features/display/screen_filter.dart';
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
  required int speedMultiplier,
  required void Function(int multiplier) onSpeedMultiplierChanged,
  required bool fullSpeed,
  required void Function(bool enabled) onFullSpeedChanged,
  required CpuType cpuType,
  required void Function(CpuType type) onCpuTypeChanged,
  required RunOptionSwitches optionSwitches,
  required void Function(RunOptionSwitches switches) onOptionSwitchesChanged,
  required Map<int, String?> fddMedia,
  required void Function(int drive) onFddInsert,
  required void Function(int drive) onFddEject,
  required Map<int, FddDriveSettings> fddDriveSettings,
  required void Function(int drive, bool enabled) onFddWriteProtectChanged,
  required void Function(int drive, bool enabled) onFddTimingChanged,
  required void Function(int drive, bool ignore) onFddCrcCheckChanged,
  required void Function(int drive, FddMediaType type) onFddInsertBlank,
  required Map<int, int> fddBankNum,
  required Map<int, int> fddCurBank,
  required void Function(int drive, int bank) onFddBankChanged,
  required Map<int, DiskSourceKind> fddSourceKind,
  required void Function(int drive) onFddSaveAs,
  required Map<int, List<FddRecentFile>> fddRecentFiles,
  required void Function(int drive, String token) onFddInsertFromRecent,
  required void Function(int drive) onFddClearRecentFiles,
  required ScreenFit screenFit,
  required void Function(ScreenFit fit) onScreenFitChanged,
  required bool scanlineEnabled,
  required void Function(bool enabled) onScanlineChanged,
  required HostScreenFilter hostFilter,
  required void Function(HostScreenFilter filter) onHostFilterChanged,
  required bool isFullscreen,
  required bool fullscreenSupported,
  required void Function(bool enabled) onFullscreenChanged,
  required void Function() onCaptureScreen,
  required bool isRecording,
  required void Function() onStartRecording,
  required void Function() onStopRecording,
  required void Function() onOpenSoundVolume,
  required void Function() onOpenJoystickAssignment,
  required bool fddMechanicalSoundEnabled,
  required void Function(bool enabled) onFddMechanicalSoundEnabledChanged,
  required bool isAutoKeying,
  required void Function() onStartAutoKey,
  required void Function() onStopAutoKey,
  required bool romajiToKana,
  required void Function(bool enabled) onRomajiToKanaChanged,
  required void Function() onOpenSaveState,
  required void Function() onOpenLoadState,
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
        MenuRadioGroup<int>(
          'control.speedMultiplier',
          label: l10n.menuControlSpeed,
          groupValue: speedMultiplier,
          options: const [
            MenuRadioOption(value: SpeedMultiplier.x1, label: 'x1'),
            MenuRadioOption(value: SpeedMultiplier.x2, label: 'x2'),
            MenuRadioOption(value: SpeedMultiplier.x4, label: 'x4'),
            MenuRadioOption(value: SpeedMultiplier.x8, label: 'x8'),
            MenuRadioOption(value: SpeedMultiplier.x16, label: 'x16'),
          ],
          onChanged: onSpeedMultiplierChanged,
        ),
        MenuCheckbox(
          'control.fullSpeed',
          label: l10n.menuControlFullSpeed,
          enabled: true,
          checked: fullSpeed,
          onChanged: onFullSpeedChanged,
        ),
        MenuRadioGroup<CpuType>(
          'control.cpuType',
          label: l10n.menuControlCpuType,
          groupValue: cpuType,
          options: const [
            MenuRadioOption(value: CpuType.fast, label: '2.0MHz'),
            MenuRadioOption(value: CpuType.slow, label: '1.2MHz'),
          ],
          onChanged: onCpuTypeChanged,
        ),
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
        MenuCheckbox(
          'control.cycleSteal',
          label: l10n.menuControlCycleSteal,
          enabled: true,
          checked: optionSwitches.cycleSteal,
          onChanged: (value) => onOptionSwitchesChanged(
            optionSwitches.copyWith(cycleSteal: value),
          ),
        ),
        MenuCheckbox(
          'control.extendedRam',
          label: l10n.menuControlExtendedRam,
          enabled: true,
          checked: optionSwitches.extendedRam,
          onChanged: (value) => onOptionSwitchesChanged(
            optionSwitches.copyWith(extendedRam: value),
          ),
        ),
        MenuCheckbox(
          'control.syncToHsync',
          label: l10n.menuControlSyncToHsync,
          enabled: true,
          checked: optionSwitches.syncToHsync,
          onChanged: (value) => onOptionSwitchesChanged(
            optionSwitches.copyWith(syncToHsync: value),
          ),
        ),
        const MenuSeparator('control.sep2'),
        MenuAction(
          'control.paste',
          label: l10n.controlPaste,
          enabled: isRunning && !isAutoKeying,
          onSelected: onStartAutoKey,
        ),
        MenuAction(
          'control.stopPaste',
          label: l10n.controlStopPaste,
          enabled: isAutoKeying,
          onSelected: onStopAutoKey,
        ),
        MenuCheckbox(
          'control.romajiToKana',
          label: l10n.controlRomajiToKana,
          enabled: true,
          checked: romajiToKana,
          onChanged: onRomajiToKanaChanged,
        ),
        const MenuSeparator('control.sep3'),
        MenuAction(
          'control.saveState',
          label: l10n.controlSaveState,
          enabled: isRunning,
          onSelected: onOpenSaveState,
        ),
        MenuAction(
          'control.loadState',
          label: l10n.controlLoadState,
          enabled: isRunning,
          onSelected: onOpenLoadState,
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
                enabled: isRunning,
                onSelected: () => onFddInsert(drive),
              ),
              MenuAction(
                'disk.fd$drive.eject',
                label: l10n.fddEject,
                enabled: isRunning && fddMedia[drive] != null,
                onSelected: () => onFddEject(drive),
              ),
              MenuAction(
                'disk.fd$drive.insertBlank2D',
                label: l10n.fddInsertBlank2D,
                enabled: isRunning,
                onSelected: () => onFddInsertBlank(drive, FddMediaType.d2),
              ),
              MenuAction(
                'disk.fd$drive.insertBlank2DD',
                label: l10n.fddInsertBlank2DD,
                enabled: isRunning,
                onSelected: () => onFddInsertBlank(drive, FddMediaType.d2dd),
              ),
              MenuCheckbox(
                'disk.fd$drive.writeProtected',
                label: l10n.fddWriteProtected,
                // 書込み保護はマウント中の媒体自身が持つ状態であり、
                // ドライブの記憶ではない（design.md「FDD拡張」）。
                // 未挿入では意味を持たないため、Ejectと同じ条件で無効化する。
                enabled: isRunning && fddMedia[drive] != null,
                checked: (fddDriveSettings[drive] ?? const FddDriveSettings())
                    .writeProtected,
                onChanged: (value) => onFddWriteProtectChanged(drive, value),
              ),
              MenuCheckbox(
                'disk.fd$drive.correctTiming',
                label: l10n.fddCorrectTiming,
                enabled: true,
                checked: (fddDriveSettings[drive] ?? const FddDriveSettings())
                    .correctTiming,
                onChanged: (value) => onFddTimingChanged(drive, value),
              ),
              MenuCheckbox(
                'disk.fd$drive.ignoreCrc',
                label: l10n.fddIgnoreCrc,
                enabled: true,
                checked: (fddDriveSettings[drive] ?? const FddDriveSettings())
                    .ignoreCrc,
                onChanged: (value) => onFddCrcCheckChanged(drive, value),
              ),
              MenuAction(
                'disk.fd$drive.saveAs',
                label: l10n.fddSaveAs,
                enabled:
                    isRunning &&
                    fddMedia[drive] != null &&
                    fddSourceKind[drive] != null &&
                    fddSourceKind[drive] != DiskSourceKind.nativeContainer,
                onSelected: () => onFddSaveAs(drive),
              ),
              if ((fddBankNum[drive] ?? 0) > 1)
                MenuRadioGroup<int>(
                  'disk.fd$drive.bank',
                  label: '',
                  groupValue: fddCurBank[drive] ?? 0,
                  options: [
                    for (var bank = 0; bank < fddBankNum[drive]!; bank++)
                      MenuRadioOption(
                        value: bank,
                        label: l10n.fddBankLabel(bank + 1),
                      ),
                  ],
                  onChanged: (bank) => onFddBankChanged(drive, bank),
                ),
              MenuSubmenu(
                'disk.fd$drive.recent',
                label: l10n.fddRecentFiles,
                entries: [
                  if ((fddRecentFiles[drive] ?? const []).isEmpty)
                    MenuAction(
                      'disk.fd$drive.recent.empty',
                      label: l10n.fddRecentFilesEmpty,
                      enabled: false,
                      onSelected: () {},
                    )
                  else
                    for (final recent in fddRecentFiles[drive]!)
                      MenuAction(
                        'disk.fd$drive.recent.${recent.token}',
                        label: recent.displayName,
                        enabled: isRunning,
                        onSelected: () =>
                            onFddInsertFromRecent(drive, recent.token),
                      ),
                  MenuSeparator('disk.fd$drive.recent.sep'),
                  MenuAction(
                    'disk.fd$drive.recent.clear',
                    label: l10n.fddClearRecentFiles,
                    enabled: (fddRecentFiles[drive] ?? const []).isNotEmpty,
                    onSelected: () => onFddClearRecentFiles(drive),
                  ),
                ],
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
          entries: [
            // OPNしか選べないため、選択済みで無効の単一ラジオとして出す
            // （design.md 12.2の`Sound > OPN [P0]`）。
            const MenuRadioGroup<String>(
              'device.sound.chip',
              label: '',
              groupValue: 'opn',
              options: [MenuRadioOption(value: 'opn', label: 'OPN')],
              onChanged: _noopStringChanged,
            ),
            const MenuSeparator('device.sound.sep0'),
            // FDD内部機構音（readWriteのみ、AUD-04）の有効・無効。
            // ホスト側合成のためコアへは送らない
            // （`EmulatorController.setFddMechanicalSoundEnabled`）。
            MenuCheckbox(
              'device.sound.fddMechanismEnabled',
              label: l10n.deviceSoundFddMechanismEnabled,
              enabled: true,
              checked: fddMechanicalSoundEnabled,
              onChanged: onFddMechanicalSoundEnabledChanged,
            ),
            // 標準OPNのFM・PSG、Beep、キーボード音、FDD機構音の個別音量
            // （AUD-03）。これらはコアのゲスト側デバイスそのものの
            // つまみであり、Host（ホスト側の最終ミックス、マスター音量）
            // とは別物のためDeviceへ置く（design.md「標準音声設定
            // （M3、AUD-03）の実装方式」）。
            MenuAction(
              'device.sound.volume',
              label: l10n.deviceSoundVolume,
              enabled: true,
              onSelected: onOpenSoundVolume,
            ),
          ],
        ),
        MenuSubmenu(
          'device.display',
          label: l10n.menuDeviceDisplay,
          entries: [
            MenuCheckbox(
              'device.display.scanline',
              label: l10n.deviceDisplayScanline,
              enabled: true,
              checked: scanlineEnabled,
              onChanged: onScanlineChanged,
            ),
          ],
        ),
        // 2台の物理ジョイスティック/ゲームパッドをJS1/JS2へ割り当てる
        // ダイアログを開く（M3 INP-04）。方向・ボタンの割当自体は固定
        // （INP-05のスコープ外）。
        MenuAction(
          'device.joystick',
          label: l10n.deviceJoystick,
          enabled: true,
          onSelected: onOpenJoystickAssignment,
        ),
      ],
    ),
    MenuGroup(
      id: MenuGroupId.host,
      label: l10n.menuHost,
      entries: [
        MenuAction(
          'host.recSound',
          label: l10n.hostRecSound,
          enabled: isRunning && !isRecording,
          onSelected: onStartRecording,
        ),
        MenuAction(
          'host.stopRecSound',
          label: l10n.hostStopRecSound,
          enabled: isRecording,
          onSelected: onStopRecording,
        ),
        MenuAction(
          'host.captureScreen',
          label: l10n.hostCaptureScreen,
          enabled: isRunning,
          onSelected: onCaptureScreen,
        ),
        const MenuSeparator('host.sep0'),
        MenuSubmenu(
          'host.screen',
          label: l10n.menuHostScreen,
          entries: [
            MenuCheckbox(
              'host.screen.fullscreen',
              label: l10n.hostScreenFullscreen,
              enabled: fullscreenSupported,
              checked: isFullscreen,
              onChanged: onFullscreenChanged,
            ),
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
            MenuRadioGroup<HostScreenFilter>(
              'host.screen.filter',
              label: l10n.hostScreenFilter,
              groupValue: hostFilter,
              options: [
                MenuRadioOption(
                  value: HostScreenFilter.rgb,
                  label: l10n.hostScreenFilterRgb,
                ),
                MenuRadioOption(
                  value: HostScreenFilter.none,
                  label: l10n.hostScreenFilterNone,
                ),
              ],
              onChanged: onHostFilterChanged,
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
