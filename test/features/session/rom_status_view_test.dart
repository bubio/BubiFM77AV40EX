import 'dart:io';

import 'package:bubi_fm77av40ex/app/l10n/generated/app_localizations.dart';
import 'package:bubi_fm77av40ex/emulator/rom/rom_probe.dart';
import 'package:bubi_fm77av40ex/features/session/rom_settings_controller.dart';
import 'package:bubi_fm77av40ex/features/session/session_providers.dart';
import 'package:bubi_fm77av40ex/features/session/widgets/rom_status_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

/// M1退出条件「ROMエラーを表示できる」の確認。
///
/// アプリと同じく、表示前に`restore()`でROMフォルダーを解決して走査する。
class _RestoringHome extends ConsumerStatefulWidget {
  const _RestoringHome();

  @override
  ConsumerState<_RestoringHome> createState() => _RestoringHomeState();
}

class _RestoringHomeState extends ConsumerState<_RestoringHome> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(romSettingsControllerProvider.notifier).restore();
    });
  }

  @override
  Widget build(BuildContext context) => const RomStatusView();
}

void main() {
  late FakePreferencesStore preferences;
  late FakeAppDataPaths appDataPaths;
  late FakeRomScanner scanner;

  setUp(() {
    preferences = FakePreferencesStore();
    appDataPaths = FakeAppDataPaths();
    scanner = FakeRomScanner();
  });

  Widget wrap(Locale locale) {
    return ProviderScope(
      overrides: [
        romSettingsControllerProvider.overrideWith(
          () => RomSettingsController(
            appDataPaths: appDataPaths,
            preferences: preferences,
            scanner: scanner,
          ),
        ),
      ],
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: const _RestoringHome(),
      ),
    );
  }

  testWidgets('APP-06 ROMフォルダーの位置と置き方を案内する', (tester) async {
    scanner.result = const [];

    await tester.pumpWidget(wrap(const Locale('ja')));
    await tester.pumpAndSettle();

    final path = tester.widget<Text>(find.byKey(const Key('romDirectoryPath')));
    expect(path.data, '/data/BubiFM77AV40EX/roms');
    expect(find.text('このフォルダーにROMファイルを置いてから、再検証してください。'), findsOneWidget);
    // 選択ダイアログの入口は出さない。
    expect(find.text('フォルダーを選択'), findsNothing);
    expect(find.text('フォルダーを開く'), findsOneWidget);
  });

  testWidgets('APP-06 ROMが1つもなければ起動できないと示す', (tester) async {
    scanner.result = const [];

    await tester.pumpWidget(wrap(const Locale('ja')));
    await tester.pumpAndSettle();

    expect(find.text('起動できません。起動必須ROMを確認してください。'), findsOneWidget);
  });

  testWidgets('SYS-01 不足ROMをファイル単位で表示する', (tester) async {
    // 起動必須のうち EXTSUB.ROM だけが欠けている。
    scanner.result = bootRequiredProbes()
      ..removeWhere((probe) => probe.fileName == 'EXTSUB.ROM');

    await tester.pumpWidget(wrap(const Locale('ja')));
    await tester.pumpAndSettle();

    expect(find.text('起動できません。起動必須ROMを確認してください。'), findsOneWidget);

    final row = find.byKey(const Key('romEntry_extsub'));
    expect(row, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.text('EXTSUB.ROM')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('見つかりません')),
      findsOneWidget,
    );
  });

  testWidgets('SYS-04 起動必須が揃えばDOSだけ可能と示す', (tester) async {
    scanner.result = bootRequiredProbes();

    await tester.pumpWidget(wrap(const Locale('ja')));
    await tester.pumpAndSettle();

    expect(find.text('DOSで起動できます。BASICにはF-BASIC ROMが必要です。'), findsOneWidget);
    // manifestがないので未検証である旨も出す。
    expect(find.text('承認済みSHA-256一覧がないため、名前とサイズだけで検証しています。'), findsOneWidget);
  });

  testWidgets('SYS-04 F-BASICが揃えばBASICでも起動できると示す', (tester) async {
    scanner.result = [
      ...bootRequiredProbes(),
      const RomProbe(
        fileName: 'FBASIC302.ROM',
        sizeInBytes: 31 * kib,
        readable: true,
      ),
    ];

    await tester.pumpWidget(wrap(const Locale('ja')));
    await tester.pumpAndSettle();

    expect(find.text('BASICとDOSのどちらでも起動できます。'), findsOneWidget);
  });

  testWidgets('走査が失敗したら失敗として示す', (tester) async {
    scanner.throwOnScan = const FileSystemException('読み取れません');

    await tester.pumpWidget(wrap(const Locale('ja')));
    await tester.pumpAndSettle();

    expect(
      find.text('ROMフォルダーを読み取れませんでした。フォルダーとアクセス権を確認してください。'),
      findsOneWidget,
    );
    // 検証していないことを、検証して正常と取り違えさせない。
    expect(find.byKey(const Key('romSummary')), findsNothing);
  });

  testWidgets('APP-01 英語ロケールでも同じ内容を出す', (tester) async {
    scanner.result = bootRequiredProbes();

    await tester.pumpWidget(wrap(const Locale('en')));
    await tester.pumpAndSettle();

    expect(
      find.text('Ready to start in DOS. BASIC needs the F-BASIC ROM.'),
      findsOneWidget,
    );
  });
}
