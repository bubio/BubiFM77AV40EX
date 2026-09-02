import 'package:bubi_fm77av40ex/app/l10n/generated/app_localizations.dart';
import 'package:bubi_fm77av40ex/app/l10n/generated/app_localizations_en.dart';
import 'package:bubi_fm77av40ex/app/menu/menu_catalog.dart';
import 'package:bubi_fm77av40ex/app/menu/menu_command.dart';
import 'package:bubi_fm77av40ex/emulator/session_state.dart';
import 'package:bubi_fm77av40ex/features/display/screen_fit.dart';
import 'package:bubi_fm77av40ex/features/settings/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Control / Disk / Device / Host`カタログの構造契約（design.md 12.2、12.3）。
///
/// P1/P2はホスト側の実装が揃うまでカタログから外す方針
/// （design.md 12.3を、未実装のP1へも同じ理由で適用）のため、
/// ここではP0項目の分類、順序、種別だけを固定する。
void main() {
  final AppLocalizations l10n = AppLocalizationsEn();

  List<MenuGroup> catalog({
    bool isRunning = true,
    BootMode bootMode = BootMode.basic,
    ScreenFit screenFit = ScreenFit.aspect,
    AppLocaleMode localeMode = AppLocaleMode.system,
  }) {
    return buildMenuCatalog(
      l10n: l10n,
      isRunning: isRunning,
      onReset: (_) {},
      bootMode: bootMode,
      onBootModeChanged: (_) {},
      fddMedia: const {},
      onFddInsert: (_) {},
      onFddEject: (_) {},
      screenFit: screenFit,
      onScreenFitChanged: (_) {},
      localeMode: localeMode,
      onLocaleModeChanged: (_) {},
    );
  }

  test('4分類をControl/Disk/Device/Hostの順で持つ', () {
    final groups = catalog();
    expect(groups.map((g) => g.id), [
      MenuGroupId.control,
      MenuGroupId.disk,
      MenuGroupId.device,
      MenuGroupId.host,
    ]);
  });

  test('Control: Reset、Special Reset、区切り、Boot Modeラジオの順', () {
    final entries = catalog()
        .firstWhere((g) => g.id == MenuGroupId.control)
        .entries;
    expect(entries, hasLength(4));
    expect(
      entries[0],
      isA<MenuAction>().having((e) => e.id, 'id', 'control.reset'),
    );
    expect(
      entries[1],
      isA<MenuAction>().having((e) => e.id, 'id', 'control.specialReset'),
    );
    expect(entries[2], isA<MenuSeparator>());
    final bootModeGroup = entries[3] as MenuRadioGroup<BootMode>;
    expect(bootModeGroup.id, 'control.bootMode');
    expect(bootModeGroup.options.map((o) => o.value), [
      BootMode.basic,
      BootMode.dos,
    ]);
  });

  test('Controlのリセット項目は停止中に無効化する', () {
    final entries = catalog(isRunning: false)
        .firstWhere((g) => g.id == MenuGroupId.control)
        .entries;
    expect((entries[0] as MenuAction).enabled, isFalse);
    expect((entries[1] as MenuAction).enabled, isFalse);
  });

  test('Disk: FD1、FD2の順でそれぞれInsert/Ejectを持つ', () {
    final entries = catalog()
        .firstWhere((g) => g.id == MenuGroupId.disk)
        .entries;
    expect(entries, hasLength(2));
    final fd1 = entries[0] as MenuSubmenu;
    expect(fd1.id, 'disk.fd0');
    expect(fd1.entries.map((e) => e.id), ['disk.fd0.insert', 'disk.fd0.eject']);
    final fd2 = entries[1] as MenuSubmenu;
    expect(fd2.id, 'disk.fd1');
  });

  test('Device: Soundサブメニューの下にOPNだけを持つ', () {
    final entries = catalog()
        .firstWhere((g) => g.id == MenuGroupId.device)
        .entries;
    expect(entries, hasLength(1));
    final sound = entries[0] as MenuSubmenu;
    expect(sound.id, 'device.sound');
    final radio = sound.entries.single as MenuRadioGroup<String>;
    expect(radio.options.map((o) => o.label), ['OPN']);
  });

  test('Host: Screen、区切り、Languageの順', () {
    final entries = catalog()
        .firstWhere((g) => g.id == MenuGroupId.host)
        .entries;
    expect(entries, hasLength(3));
    expect(
      entries[0],
      isA<MenuSubmenu>().having((e) => e.id, 'id', 'host.screen'),
    );
    expect(entries[1], isA<MenuSeparator>());
    expect(
      entries[2],
      isA<MenuSubmenu>().having((e) => e.id, 'id', 'host.language'),
    );
  });

  test('Host > Screenのラジオはaspect/integer/fillの順', () {
    final host = catalog().firstWhere((g) => g.id == MenuGroupId.host).entries;
    final screen = host[0] as MenuSubmenu;
    final fit = screen.entries.single as MenuRadioGroup<ScreenFit>;
    expect(fit.options.map((o) => o.value), [
      ScreenFit.aspect,
      ScreenFit.integer,
      ScreenFit.fill,
    ]);
  });

  test('Host > Languageのラジオはsystem/english/japaneseの順', () {
    final host = catalog().firstWhere((g) => g.id == MenuGroupId.host).entries;
    final language = host[2] as MenuSubmenu;
    final mode = language.entries.single as MenuRadioGroup<AppLocaleMode>;
    expect(mode.options.map((o) => o.value), [
      AppLocaleMode.system,
      AppLocaleMode.english,
      AppLocaleMode.japanese,
    ]);
  });
}
