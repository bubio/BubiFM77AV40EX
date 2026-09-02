import 'package:flutter/material.dart';

import 'menu_command.dart';

/// [buildMenuCatalog]が返す`Control / Disk / Device / Host`をアプリ内
/// メニューとして描画する（design.md 12.1）。
///
/// macOSでは`Application`をここに含めず、`PlatformApplicationMenu`が
/// OS標準メニューへ出す。WindowsとLinuxでは`Application`を含めた同じ
/// カタログをここへ渡す想定（design.md 12.1）だが、対象はM4/M5であり
/// 現時点ではmacOS向けの分類だけを渡す。
class AppMenuBar extends StatelessWidget {
  const AppMenuBar({super.key, required this.groups, required this.child});

  final List<MenuGroup> groups;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 既定の`MenuBar`は角丸・影付きの浮動カードとして描画され、ネイティブの
    // 通し帯のメニューバーには見えない
    // （https://api.flutter.dev/flutter/material/MenuBar-class.html）。
    // 背景と下境界線を持つ全幅の`Container`を土台にし、`MenuBar`自体は
    // 角丸・影・背景を持たない透明な帯として左詰めで重ねる。
    return Column(
      children: [
        Container(
          width: double.infinity,
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            border: Border(bottom: BorderSide(color: theme.dividerColor)),
          ),
          child: MenuBar(
            style: MenuStyle(
              backgroundColor: const WidgetStatePropertyAll(Colors.transparent),
              shadowColor: const WidgetStatePropertyAll(Colors.transparent),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              elevation: const WidgetStatePropertyAll(0),
              shape: const WidgetStatePropertyAll(RoundedRectangleBorder()),
              padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            ),
            children: [
              for (final group in groups)
                SubmenuButton(
                  menuChildren: [
                    for (final entry in group.entries) _build(entry),
                  ],
                  child: Text(group.label),
                ),
            ],
          ),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _build(MenuEntry entry) {
    return switch (entry) {
      MenuSeparator() => const Divider(height: 1),
      MenuAction() => MenuItemButton(
        onPressed: entry.enabled ? entry.onSelected : null,
        child: Text(entry.label),
      ),
      MenuCheckbox() => CheckboxMenuButton(
        value: entry.checked,
        onChanged: entry.enabled
            ? (value) => entry.onChanged(value ?? false)
            : null,
        child: Text(entry.label),
      ),
      MenuRadioGroup<dynamic>() => _buildRadioGroup(entry),
      MenuSubmenu() => SubmenuButton(
        menuChildren: [for (final child in entry.entries) _build(child)],
        child: Text(entry.label),
      ),
    };
  }

  Widget _buildRadioGroup(MenuRadioGroup<dynamic> group) {
    return SubmenuButton(
      menuChildren: [
        for (final option in group.options) _radioItem(group, option),
      ],
      child: Text(
        group.label.isEmpty ? _radioSelectedLabel(group) : group.label,
      ),
    );
  }

  // `MenuRadioGroup<T>`の実際のTは呼び出し元（`_build`）の時点で
  // `dynamic`へ消えている（`switch`の型パターンによる型テストの結果、
  // 静的型がそこで失われるため）。`RadioMenuButton<T>`をTごとに
  // 作り分けようとすると、その消えたTでインスタンス化してしまい、
  // フィールドの実際の関数型との不一致で実行時に失敗する
  // （選択が効かない壊れ方をする。実際に再現・確認済み）。
  // ここでは常に`RadioMenuButton<Object?>`を使い、値の比較は`==`だけに
  // 頼ることでTへの依存自体をなくす。選択時は`MenuRadioGroup.changeTo`
  // （型を消した形の`onChanged`呼び出し）へ委ねる。
  Widget _radioItem(
    MenuRadioGroup<dynamic> entry,
    MenuRadioOption<dynamic> option,
  ) {
    return RadioMenuButton<Object?>(
      value: option.value,
      groupValue: entry.groupValue,
      onChanged: option.enabled
          ? (value) {
              if (value != null) {
                entry.changeTo(value);
              }
            }
          : null,
      child: Text(option.label),
    );
  }

  String _radioSelectedLabel(MenuRadioGroup<dynamic> entry) {
    for (final option in entry.options) {
      if (option.value == entry.groupValue) {
        return option.label;
      }
    }
    return '';
  }
}
