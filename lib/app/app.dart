import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'l10n/generated/app_localizations.dart';

/// アプリケーションのルート。
///
/// M0時点では画面構成を持たず、ローカライズとテーマの土台だけを提供する。
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
      home: const _PlaceholderHome(),
    );
  }
}

class _PlaceholderHome extends StatelessWidget {
  const _PlaceholderHome();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Text(l10n.appTitle, style: const TextStyle(color: Colors.white)),
      ),
    );
  }
}
