/// `Control / Disk / Device / Host`アプリ内メニューとmacOS標準
/// Applicationメニューが共有するカタログのデータ型（design.md 12.1〜12.3）。
///
/// Flutterの`MenuBar`や`PlatformMenuBar`へ依存しない、純粋なデータ構造に
/// するのは、同じカタログから複数のOS表現（アプリ内メニュー、macOS標準
/// メニュー、将来のAndroid/iOSオーバーフロー）を組み立てるためと、
/// Widgetなしで構造をテストできるようにするためである。
library;

/// メニューの最上位分類（design.md 12.1）。
enum MenuGroupId { application, control, disk, device, host }

sealed class MenuEntry {
  const MenuEntry(this.id);

  /// 版を跨いで変えない安定したID（design.md 12.3）。
  final String id;
}

/// 区切り線。
class MenuSeparator extends MenuEntry {
  const MenuSeparator(super.id);
}

/// 選ぶと即座に実行される項目。
class MenuAction extends MenuEntry {
  const MenuAction(
    super.id, {
    required this.label,
    required this.enabled,
    required this.onSelected,
  });

  final String label;
  final bool enabled;
  final void Function() onSelected;
}

/// コマンド完了後の実状態を表示するチェック項目（design.md 12.3）。
class MenuCheckbox extends MenuEntry {
  const MenuCheckbox(
    super.id, {
    required this.label,
    required this.enabled,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final bool enabled;
  final bool checked;
  final void Function(bool value) onChanged;
}

class MenuRadioOption<T> {
  const MenuRadioOption({
    required this.value,
    required this.label,
    this.enabled = true,
  });

  final T value;
  final String label;
  final bool enabled;
}

/// 設定値と常に一つだけ一致するラジオ群（design.md 12.3）。
class MenuRadioGroup<T> extends MenuEntry {
  const MenuRadioGroup(
    super.id, {
    required this.label,
    required this.groupValue,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T groupValue;
  final List<MenuRadioOption<T>> options;
  final void Function(T value) onChanged;
}

/// 子項目を持つサブメニュー。
class MenuSubmenu extends MenuEntry {
  const MenuSubmenu(super.id, {required this.label, required this.entries});

  final String label;
  final List<MenuEntry> entries;
}

/// `Control`、`Disk`、`Device`、`Host`のいずれか一分類。
class MenuGroup {
  const MenuGroup({
    required this.id,
    required this.label,
    required this.entries,
  });

  final MenuGroupId id;
  final String label;
  final List<MenuEntry> entries;
}
