import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/session/session_providers.dart';
import '../features/session/widgets/rom_status_view.dart';
import 'l10n/generated/app_localizations.dart';

/// アプリケーションのルート。
///
/// M1 WP2時点ではROM設定画面だけを出す。
/// エミュレーター画面とステータスバーはM2 WP6で追加する。
class BubiFm77Av40ExApp extends StatelessWidget {
  const BubiFm77Av40ExApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const _Home(),
    );
  }
}

/// 起動直後に保存済みのROM設定を復元してから画面を出す。
class _Home extends ConsumerStatefulWidget {
  const _Home();

  @override
  ConsumerState<_Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<_Home> {
  @override
  void initState() {
    super.initState();
    // 復元は失敗しても画面を出す。アクセス権の失効と走査の失敗は
    // Controllerが状態として持ち、画面に出す。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(romSettingsControllerProvider.notifier).restore();
    });
  }

  @override
  Widget build(BuildContext context) => const RomStatusView();
}
