import 'package:bubifm77av40ex/app/l10n/generated/app_localizations.dart';
import 'package:bubifm77av40ex/app/menu/sound_volume_dialog.dart';
import 'package:bubifm77av40ex/emulator/session_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Device > Sound > Volume…`が開くダイアログ（specification.md AUD-03）。
///
/// 5チャンネル分のスライダーが表示され、操作すると対応する[SoundChannel]で
/// [SoundVolumeDialog.onChanged]が呼ばれることと、動かしたスライダー自身の
/// 見た目（`value`）がその場で追従することを確認する
/// （`ref.read`で渡した開いた時点の値のまま固まらないこと。design.md
/// 「標準音声設定（M3、AUD-03）の実装方式」）。
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required SoundChannelVolumes volumes,
    required void Function(SoundChannel channel, double volume) onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) => SoundVolumeDialog(
              l10n: AppLocalizations.of(context),
              volumes: volumes,
              onChanged: onChanged,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('5チャンネルぶんのスライダーを表示する', (tester) async {
    await pump(
      tester,
      volumes: const SoundChannelVolumes(),
      onChanged: (_, _) {},
    );

    expect(find.byType(Slider), findsNWidgets(SoundChannel.values.length));
  });

  testWidgets('スライダーを操作すると対応するSoundChannelでonChangedが呼ばれる', (tester) async {
    SoundChannel? changedChannel;
    double? changedVolume;
    await pump(
      tester,
      volumes: const SoundChannelVolumes(),
      onChanged: (channel, volume) {
        changedChannel = channel;
        changedVolume = volume;
      },
    );

    // 2番目のスライダー（opnPsg）を左端までドラッグする。
    await tester.drag(find.byType(Slider).at(1), const Offset(-1000, 0));
    await tester.pump();

    expect(changedChannel, SoundChannel.opnPsg);
    expect(changedVolume, 0.0);
    // ドラッグしたスライダー自身の見た目も追従する（元の値のまま
    // 固まらない）。他のスライダーは動かしていないので既定のまま。
    expect(tester.widget<Slider>(find.byType(Slider).at(1)).value, 0.0);
    expect(tester.widget<Slider>(find.byType(Slider).at(0)).value, 1.0);
  });
}
