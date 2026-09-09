import 'package:bubifm77av40ex/platform/audio/fdd_mechanical_sound.dart';
import 'package:flutter_test/flutter_test.dart';

/// FDD内部機構音（readWriteのみ、AUD-04）の純Dart合成器の単体テスト。
///
/// AUD-04着手前の技術検証ゲートで、seek・ヘッドロード／アンロードは
/// コア無改変では観測不能と判明したため、ここではドライブの読み書き
/// アクセス1種類だけを検証する（design.md 7.1、development_plan.md
/// §5.3「FDDイベント」）。
void main() {
  test('イベントが無ければ無音を返す', () {
    final synth = FddMechanicalSound();

    final out = synth.renderInterleavedStereo(1000);

    expect(out.every((sample) => sample == 0), isTrue);
  });

  test('同一のイベント列とrender呼び出し列からは同一のPCMが得られる（決定性）', () {
    final a = FddMechanicalSound(seed: 42);
    final b = FddMechanicalSound(seed: 42);

    a.notifyDriveAccess({0});
    b.notifyDriveAccess({0});
    final outA1 = a.renderInterleavedStereo(500);
    final outB1 = b.renderInterleavedStereo(500);
    a.notifyDriveAccess({1});
    b.notifyDriveAccess({1});
    final outA2 = a.renderInterleavedStereo(500);
    final outB2 = b.renderInterleavedStereo(500);

    expect(outA1, outB1);
    expect(outA2, outB2);
  });

  test('1イベントは有界長のバーストを生成し、その後は無音に戻る', () {
    final synth = FddMechanicalSound();
    synth.notifyDriveAccess({0});

    // sampleRate既定44100、バースト長は約15ms（≒662フレーム）。
    // 十分な余裕を持って2000フレーム分描画する。
    final out = synth.renderInterleavedStereo(2000);

    final hasEnergyEarly = out.sublist(0, 1300).any((sample) => sample != 0);
    expect(hasEnergyEarly, isTrue);

    // バースト長を大きく超えた末尾では鳴っていない。
    final tail = out.sublist(out.length - 400);
    expect(tail.every((sample) => sample == 0), isTrue);
  });

  test('クールダウン中の連打は新しいバーストを追加しない', () {
    final withOneTrigger = FddMechanicalSound(seed: 7);
    withOneTrigger.notifyDriveAccess({0});
    final outOnce = withOneTrigger.renderInterleavedStereo(2000);

    final withRepeatedTrigger = FddMechanicalSound(seed: 7);
    // render()を挟まずに連打すると、内部の経過フレーム数が進まないため
    // クールダウン判定上は「同時刻の連打」になり、抑制される。
    withRepeatedTrigger.notifyDriveAccess({0});
    withRepeatedTrigger.notifyDriveAccess({0});
    withRepeatedTrigger.notifyDriveAccess({0});
    final outRepeated = withRepeatedTrigger.renderInterleavedStereo(2000);

    expect(outRepeated, outOnce);
  });

  test('同時多発イベントでもvoice数上限を超えて破綻しない', () {
    final synth = FddMechanicalSound();

    synth.notifyDriveAccess({0, 1, 2, 3, 4, 5, 6, 7, 8, 9});
    final out = synth.renderInterleavedStereo(4000);

    expect(out.every((sample) => sample >= -32768 && sample <= 32767), isTrue);
  });
}
