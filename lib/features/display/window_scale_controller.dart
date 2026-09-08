import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/persistence/window_scale.dart';

/// ウィンドウ倍率の状態（design.md 12.2 `Host > Screen > Window x1/x2/…`）。
///
/// [availableMultipliers]は主ディスプレイの作業領域に収まる倍率だけを持つ
/// （動的ラジオ、design.md 12.2「区切り線と項目順も設計の一部」と同じく
/// 一覧自体が実行時条件で変わる）。[currentMultiplier]は実際のウィンドウ
/// サイズから逆算した値で、どの倍率とも一致しなければ`null`（利用者が
/// ドラッグで任意サイズへ変えた直後など）。
typedef WindowScaleState = ({
  bool supported,
  List<int> availableMultipliers,
  int? currentMultiplier,
});

const _unsupportedWindowScaleState = (
  supported: false,
  availableMultipliers: <int>[],
  currentMultiplier: null,
);

/// メインウィンドウの倍率変更を扱う（design.md 12.2 `Host > Screen`）。
///
/// OS操作（ドラッグでのリサイズ）でも変わるため、[setMultiplier]はコマンド
/// を送るだけで、実際の状態反映は[WindowScale.contentSizeChanges]の通知を
/// 待つ（[FullscreenController]と同じ設計、design.md 12.3「チェック項目は
/// コマンド完了後の実状態を表示する」）。
class WindowScaleController extends Notifier<WindowScaleState> {
  WindowScaleController({required this.windowScale});

  final WindowScale windowScale;

  /// 倍率の計算対象になるゲスト画面サイズ（論理px）。[setBaseSize]が
  /// `EmulatorViewState.frameWidth/frameHeight`から更新する。
  Size _baseSize = const Size(640, 400);

  /// ウィンドウ内容領域のうち、ゲスト画面以外が占める高さ（論理px）。
  /// [setChromeHeight]が`Host > Show Status Bar`の表示状態から更新する。
  /// これを含めて倍率を計算しないと、x1で選んでもゲスト画面自体が
  /// 640x400にならない（design.md「Window x1/x2/…の実装方式」）。
  double _chromeHeight = 0;

  /// [applyInitialMultiplierIfNeeded]を一度だけ実行するためのガード。
  bool _initialMultiplierApplied = false;

  StreamSubscription<Size>? _subscription;

  @override
  WindowScaleState build() {
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
    });
    unawaited(_initialize());
    return _unsupportedWindowScaleState;
  }

  Future<void> _initialize() async {
    if (!await windowScale.isSupported) {
      return;
    }
    await _refresh();
    _subscription = windowScale.contentSizeChanges.listen((_) {
      unawaited(_refresh());
    });
  }

  /// ゲスト画面サイズが変わったら倍率候補・現在値を再計算する。
  Future<void> setBaseSize(Size size) async {
    if (_baseSize == size) {
      return;
    }
    _baseSize = size;
    if (state.supported) {
      await _refresh();
    }
  }

  /// ゲスト画面以外が占める高さ（ステータスバー等）が変わったら
  /// 倍率候補・現在値を再計算する。
  Future<void> setChromeHeight(double height) async {
    if (_chromeHeight == height) {
      return;
    }
    _chromeHeight = height;
    if (state.supported) {
      await _refresh();
    }
  }

  Size _windowSizeForMultiplier(int multiplier) => Size(
    _baseSize.width * multiplier,
    _baseSize.height * multiplier + _chromeHeight,
  );

  Future<void> _refresh() async {
    final display = await windowScale.getAvailableDisplaySize();
    final maxByWidth = (display.width / _baseSize.width).floor();
    final maxByHeight = ((display.height - _chromeHeight) / _baseSize.height)
        .floor();
    final rawMax = maxByWidth < maxByHeight ? maxByWidth : maxByHeight;
    // 画面が極端に小さくても最低x1は候補に残す。
    final maxMultiplier = rawMax < 1 ? 1 : rawMax;
    final multipliers = [for (var m = 1; m <= maxMultiplier; m++) m];

    final current = await windowScale.getContentSize();
    int? matched;
    for (final m in multipliers) {
      final target = _windowSizeForMultiplier(m);
      if ((current.width - target.width).abs() < 1 &&
          (current.height - target.height).abs() < 1) {
        matched = m;
        break;
      }
    }
    state = (
      supported: true,
      availableMultipliers: multipliers,
      currentMultiplier: matched,
    );
  }

  /// ウィンドウをゲスト画面の[multiplier]倍へリサイズする。
  Future<void> setMultiplier(int multiplier) async {
    if (!state.supported) {
      return;
    }
    await windowScale.setContentSize(_windowSizeForMultiplier(multiplier));
    await _refresh();
  }

  /// 起動直後、まだどの倍率とも一致していなければx1へ合わせてから
  /// ウィンドウを表示する。
  ///
  /// ネイティブ側のウィンドウ初期フレームはゲスト画面と無関係な既定値
  /// （xibの固定サイズ）のため、何もしなければアスペクト比が合わず
  /// 映像が左右に黒帯で挟まれる（design.md「Window x1/x2/…の実装方式」、
  /// 利用者からの報告で発覚）。ウィンドウは`MainFlutterWindow.swift`が
  /// 起動直後に隠しているため、このリサイズが終わるまでは画面に出ない
  /// （利用者から「起動時に既定サイズで一瞬表示されてからx1へ変わって
  /// 見える」との指摘を受け、隠す→合わせる→出す の順に変更した）。
  /// 呼び出し側（`app.dart`）は[setChromeHeight]が実測値（メニュー帯の
  /// 高さ）で更新された後に呼ぶこと——それより前に呼ぶと、まだ0の
  /// chromeHeightでx1へ合わせてしまい、以後[state]が`currentMultiplier`と
  /// 一致した扱いになって`_refresh`のたびの再調整が起きなくなる。
  Future<void> applyInitialMultiplierIfNeeded() async {
    if (_initialMultiplierApplied || !state.supported) {
      return;
    }
    _initialMultiplierApplied = true;
    await _refresh();
    if (state.currentMultiplier == null &&
        state.availableMultipliers.isNotEmpty) {
      await setMultiplier(1);
    }
    await windowScale.show();
  }
}

final windowScaleControllerProvider =
    NotifierProvider<WindowScaleController, WindowScaleState>(
      () => throw UnimplementedError('appがoverrideWithで組み立てる'),
    );
