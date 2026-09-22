import 'package:bubifm77av40ex/app/l10n/generated/app_localizations.dart';
import 'package:bubifm77av40ex/app/menu/sound_volume_dialog.dart';
import 'package:bubifm77av40ex/emulator/session_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// `Host > Sound > Volume…`が開くダイアログ（specification.md AUD-03、
/// AUD-07統合）。
///
/// 標準音声5チャンネル＋CMT 2チャンネル分のスライダーが表示され、
/// 操作すると対応するコールバックが呼ばれることと、動かしたスライダー自身の
/// 見た目（`value`）がその場で追従することを確認する
/// （`ref.read`で渡した開いた時点の値のまま固まらないこと。design.md
/// 「標準音声設定（M3、AUD-03）の実装方式」）。
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required SoundChannelVolumes volumes,
    required void Function(SoundChannel channel, double volume) onChanged,
    CmtSoundSettings cmtSettings = const CmtSoundSettings(),
    void Function(CmtSoundKind kind, double volume)? onCmtChanged,
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
              cmtSettings: cmtSettings,
              onCmtChanged: onCmtChanged ?? (_, _) {},
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('標準音声5チャンネル＋CMT 2チャンネル分のスライダーを表示する', (tester) async {
    await pump(
      tester,
      volumes: const SoundChannelVolumes(),
      onChanged: (_, _) {},
    );

    // SoundChannel 5本 + CmtSoundKind.noise・signal の 2本 = 7本
    // （CmtSoundKind.voiceは音量調整不可のためスライダーなし）
    expect(find.byType(Slider), findsNWidgets(SoundChannel.values.length + 2));
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

  testWidgets('CMTスライダーを操作するとonCmtChangedが呼ばれる', (tester) async {
    CmtSoundKind? changedKind;
    double? changedVolume;
    await pump(
      tester,
      volumes: const SoundChannelVolumes(),
      onChanged: (_, _) {},
      cmtSettings: const CmtSoundSettings(noiseVolume: 0.8, signalVolume: 0.6),
      onCmtChanged: (kind, volume) {
        changedKind = kind;
        changedVolume = volume;
      },
    );

    // SoundChannel 5本の後にCMTスライダーが続く。
    // インデックス5がCMT機構音、インデックス6がCMT信号。
    final noiseSlider = find.byType(Slider).at(5);
    await tester.ensureVisible(noiseSlider);
    await tester.pumpAndSettle();
    await tester.drag(noiseSlider, const Offset(-1000, 0));
    await tester.pump();

    expect(changedKind, CmtSoundKind.noise);
    expect(changedVolume, 0.0);
    expect(tester.widget<Slider>(find.byType(Slider).at(5)).value, 0.0);
    // CMT信号スライダーは動かしていないので元の値のまま。
    expect(
      tester.widget<Slider>(find.byType(Slider).at(6)).value,
      closeTo(0.6, 0.01),
    );
  });
}
