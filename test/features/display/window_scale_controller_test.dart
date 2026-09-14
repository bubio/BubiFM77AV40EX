import 'dart:ui';

import 'package:bubifm77av40ex/features/display/window_scale_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late FakeWindowScale windowScale;
  late FakeWindowChrome windowChrome;
  late FakePreferencesStore preferences;
  late ProviderContainer container;

  setUp(() {
    windowScale = FakeWindowScale();
    windowChrome = FakeWindowChrome();
    preferences = FakePreferencesStore();
    container = ProviderContainer(
      overrides: [
        windowScaleControllerProvider.overrideWith(
          () => WindowScaleController(
            windowScale: windowScale,
            windowChrome: windowChrome,
            preferences: preferences,
          ),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
  });

  test('未対応OSでは倍率候補が空のまま', () async {
    windowScale.supported = false;
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(windowScaleControllerProvider);
    expect(state.supported, isFalse);
    expect(state.availableMultipliers, isEmpty);
  });

  test('起動時にディスプレイの作業領域から収まる倍率一覧を作る', () async {
    // 既定のゲスト画面サイズ640x400、ディスプレイ1920x1080なら
    // floor(1920/640)=3、floor(1080/400)=2なのでx1,x2まで。
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final state = container.read(windowScaleControllerProvider);
    expect(state.supported, isTrue);
    expect(state.availableMultipliers, [1, 2]);
  });

  test('現在のウィンドウサイズがどの倍率とも一致しなければnull', () async {
    windowScale.contentSize = const Size(999, 999);
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(windowScaleControllerProvider).currentMultiplier,
      isNull,
    );
  });

  test('現在のウィンドウサイズが倍率と一致すればその値を返す', () async {
    windowScale.contentSize = const Size(1280, 800);
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(windowScaleControllerProvider).currentMultiplier, 2);
  });

  test('setMultiplierはゲスト画面サイズのn倍でウィンドウサイズを変える', () async {
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(windowScaleControllerProvider.notifier);
    await controller.setMultiplier(2);

    expect(windowScale.setContentSizeCalls, [const Size(1280, 800)]);
    expect(container.read(windowScaleControllerProvider).currentMultiplier, 2);
  });

  test('未対応OSではsetMultiplierは何もしない', () async {
    windowScale.supported = false;
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(windowScaleControllerProvider.notifier);
    await controller.setMultiplier(2);

    expect(windowScale.setContentSizeCalls, isEmpty);
  });

  test('OS側のリサイズ（ドラッグ操作）で現在値が更新される', () async {
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    windowScale.emit(const Size(1920, 1200));
    await Future<void>.delayed(Duration.zero);

    // ディスプレイに収まらないサイズへドラッグされても倍率候補自体は
    // ディスプレイ作業領域基準のまま変わらない。
    final state = container.read(windowScaleControllerProvider);
    expect(state.availableMultipliers, [1, 2]);
    expect(state.currentMultiplier, isNull);
  });

  test('setChromeHeight未設定（0）ではステータスバー分だけ足りないサイズは'
      'どの倍率とも一致しない', () async {
    windowScale.contentSize = const Size(640, 424);
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(windowScaleControllerProvider).currentMultiplier,
      isNull,
    );
  });

  test('setChromeHeightを反映すると、ステータスバー分を含むサイズがx1と一致する', () async {
    windowScale.contentSize = const Size(640, 424);
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(windowScaleControllerProvider.notifier);
    await controller.setChromeHeight(24);

    expect(container.read(windowScaleControllerProvider).currentMultiplier, 1);
  });

  test('setMultiplierはchromeHeightを含めた高さでウィンドウサイズを変える', () async {
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(windowScaleControllerProvider.notifier);
    await controller.setChromeHeight(24);
    await controller.setMultiplier(1);

    expect(windowScale.setContentSizeCalls, [const Size(640, 424)]);
    expect(container.read(windowScaleControllerProvider).currentMultiplier, 1);
  });

  test('setMultiplierで選んだ倍率をPreferencesStoreへ保存する', () async {
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(windowScaleControllerProvider.notifier);
    await controller.setMultiplier(2);

    expect(preferences.getInt('settings.windowMultiplier'), 2);
  });

  test('ドラッグで倍率と一致するサイズになった場合も保存する', () async {
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    windowScale.emit(const Size(1280, 800));
    await Future<void>.delayed(Duration.zero);

    expect(preferences.getInt('settings.windowMultiplier'), 2);
  });

  test('applyInitialMultiplierIfNeededは保存済みの倍率があればそれへ合わせる', () async {
    preferences.values['settings.windowMultiplier'] = 2;
    windowScale.contentSize = const Size(800, 600);
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(windowScaleControllerProvider.notifier);
    await controller.applyInitialMultiplierIfNeeded();

    expect(windowScale.setContentSizeCalls, [const Size(1280, 800)]);
    expect(container.read(windowScaleControllerProvider).currentMultiplier, 2);
  });

  test('保存済みの倍率が現在のディスプレイで選べなければx1へ合わせる', () async {
    preferences.values['settings.windowMultiplier'] = 5;
    windowScale.contentSize = const Size(800, 600);
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(windowScaleControllerProvider.notifier);
    await controller.applyInitialMultiplierIfNeeded();

    expect(windowScale.setContentSizeCalls, [const Size(640, 400)]);
  });

  test('applyInitialMultiplierIfNeededは起動直後の未一致サイズをx1へ合わせる', () async {
    // ネイティブ側の初期フレームはゲスト画面と無関係（xibの固定サイズ）。
    windowScale.contentSize = const Size(800, 600);
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(windowScaleControllerProvider.notifier);
    await controller.applyInitialMultiplierIfNeeded();

    expect(windowScale.setContentSizeCalls, [const Size(640, 400)]);
    expect(container.read(windowScaleControllerProvider).currentMultiplier, 1);
  });

  test('applyInitialMultiplierIfNeededは既にどれかの倍率と一致していれば何もしない', () async {
    windowScale.contentSize = const Size(640, 400);
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(windowScaleControllerProvider.notifier);
    await controller.applyInitialMultiplierIfNeeded();

    expect(windowScale.setContentSizeCalls, isEmpty);
  });

  test('applyInitialMultiplierIfNeededは一度しか実行しない', () async {
    windowScale.contentSize = const Size(800, 600);
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(windowScaleControllerProvider.notifier);
    await controller.applyInitialMultiplierIfNeeded();
    // 手動でx2へ変えても、再度呼んだだけでx1へ戻されては困る。
    await controller.setMultiplier(2);
    await controller.applyInitialMultiplierIfNeeded();

    expect(windowScale.setContentSizeCalls, [
      const Size(640, 400),
      const Size(1280, 800),
    ]);
  });

  test('applyInitialMultiplierIfNeededはサイズを合わせた後にウィンドウを表示する', () async {
    windowScale.contentSize = const Size(800, 600);
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(windowScaleControllerProvider.notifier);
    await controller.applyInitialMultiplierIfNeeded();

    expect(windowScale.showCalls, 1);
  });

  test('未対応OSではapplyInitialMultiplierIfNeededはウィンドウを表示しない', () async {
    windowScale.supported = false;
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(windowScaleControllerProvider.notifier);
    await controller.applyInitialMultiplierIfNeeded();

    expect(windowScale.showCalls, 0);
  });

  test('フルスクリーン中はウィンドウの実サイズが変わっても現在値を再計算しない', () async {
    windowScale.contentSize = const Size(1280, 800);
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);
    expect(container.read(windowScaleControllerProvider).currentMultiplier, 2);

    windowChrome.emit(true);
    windowScale.emit(const Size(1920, 1080));
    await Future<void>.delayed(Duration.zero);

    // フルスクリーンで実サイズがディスプレイ全体になっても、フルスクリーン
    // 化直前のx2表示のまま（利用者からの報告：「フルスクリーンにすると
    // 倍率メニューが空欄になる」への対応）。
    expect(container.read(windowScaleControllerProvider).currentMultiplier, 2);
  });

  test('フルスクリーン解除後はウィンドウの実サイズから現在値を再計算する', () async {
    windowScale.contentSize = const Size(1280, 800);
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    windowChrome.emit(true);
    windowScale.emit(const Size(1920, 1080));
    await Future<void>.delayed(Duration.zero);

    windowChrome.emit(false);
    windowScale.emit(const Size(640, 400));
    await Future<void>.delayed(Duration.zero);

    expect(container.read(windowScaleControllerProvider).currentMultiplier, 1);
  });

  test('フルスクリーン未対応OSでは通常どおり実サイズから現在値を再計算する', () async {
    windowChrome.supported = false;
    windowScale.contentSize = const Size(1280, 800);
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    windowScale.emit(const Size(1920, 1080));
    await Future<void>.delayed(Duration.zero);

    expect(
      container.read(windowScaleControllerProvider).currentMultiplier,
      isNull,
    );
  });

  test('setBaseSizeでゲスト画面サイズが変わると倍率候補を再計算する', () async {
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(windowScaleControllerProvider.notifier);
    // floor(1920/960)=2、floor(1080/640)=1なのでx1のみ。
    await controller.setBaseSize(const Size(960, 640));

    expect(container.read(windowScaleControllerProvider).availableMultipliers, [
      1,
    ]);
  });

  test('起動時にウィンドウの最小サイズをx1のサイズへ設定する', () async {
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    expect(windowScale.setMinimumContentSizeCalls.last, const Size(640, 400));
  });

  test('setChromeHeightを反映すると最小サイズにも足す', () async {
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(windowScaleControllerProvider.notifier);
    await controller.setChromeHeight(24);

    expect(windowScale.setMinimumContentSizeCalls.last, const Size(640, 424));
  });

  test('setBaseSizeが変わると最小サイズも新しいx1サイズへ更新する', () async {
    container.read(windowScaleControllerProvider);
    await Future<void>.delayed(Duration.zero);

    final controller = container.read(windowScaleControllerProvider.notifier);
    await controller.setBaseSize(const Size(960, 640));

    expect(windowScale.setMinimumContentSizeCalls.last, const Size(960, 640));
  });
}
