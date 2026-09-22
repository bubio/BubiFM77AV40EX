import 'dart:async';
import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/persistence/preferences_store.dart';
import '../../platform/persistence/window_chrome.dart';
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
  WindowScaleController({
    required this.windowScale,
    required this.windowChrome,
    required this.preferences,
  });

  final WindowScale windowScale;

  /// 選択した倍率を再起動後も復元するための保存先
  /// （design.md 12.2 `Host > Screen > Window x1/x2/…`、利用者からの
  /// 指摘：「起動のたびにx1へ戻ってしまう」）。
  final PreferencesStore preferences;

  static const String _multiplierKey = 'settings.windowMultiplier';

  /// [_refresh]で書き込むたびに`PreferencesStore`へ触れないための直近値。
  int? _lastPersistedMultiplier;

  /// フルスクリーン中かどうかを都度[FullscreenController]を介さず直接
  /// 問い合わせるために持つ（design.mdの倍率メニュー、design.md 12.3の
  /// 「チェック項目はコマンド完了後の実状態を表示する」と同じ考え方）。
  /// フルスクリーン中はウィンドウの実サイズがディスプレイ全体になり、
  /// どの倍率とも一致しなくなるため、[_refresh]をスキップしてフルスクリーン
  /// 化直前の表示をそのまま保つ（利用者からの報告：「フルスクリーンにすると
  /// 倍率メニューが空欄になる」）。
  final WindowChrome windowChrome;

  /// フルスクリーン対応OSかどうか（[_initialize]で一度だけ確定）。
  /// 未対応OSで[windowChrome.isFullScreen]を呼ぶと
  /// [MissingPluginException]になるため、事前にこれで分岐する。
  bool _fullscreenSupported = false;

  /// 倍率の計算対象になるゲスト画面サイズ（論理px）。[setBaseSize]が
  /// `EmulatorViewState.frameWidth/frameHeight`から更新する。
  Size _baseSize = const Size(640, 400);

  /// ウィンドウ内容領域のうち、ゲスト画面以外が占める高さ（論理px）。
  /// [setChromeHeight]が`Host > Show Status Bar`の表示状態から更新する。
  /// これを含めて倍率を計算しないと、x1で選んでもゲスト画面自体が
  /// 640x400にならない（design.md「Window x1/x2/…の実装方式」）。
  double _chromeHeight = 0;

  /// 起動時点で保存されていた倍率。[_refresh]は一致した倍率を保存するため、
  /// 初期フレームが偶然x1と一致すると（Linuxはネイティブ側の既定サイズを
  /// x1にしてある）保存済みの値が上書きされる。その前に読んでおき、
  /// [applyInitialMultiplierIfNeeded]で使う。
  int? _storedMultiplierAtStartup;

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
    _fullscreenSupported = await windowChrome.isSupported;
    _storedMultiplierAtStartup = preferences.getInt(_multiplierKey);
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
  ///
  /// 既にどれかの倍率と一致していた場合は、ウィンドウの実サイズを新しい
  /// chromeHeightに合わせて能動的にリサイズし、同じ倍率を保つ（`Host >
  /// Show Status Bar`の表示切替直後にウィンドウサイズが変わらず、ゲスト
  /// 画面だけがステータスバー分伸び縮みして見える不具合への対応）。
  /// 一致していなければ（利用者がドラッグで任意サイズにした直後など）、
  /// 従来どおり値の再計算だけに留める。
  Future<void> setChromeHeight(double height) async {
    if (_chromeHeight == height) {
      return;
    }
    final previousMultiplier = state.currentMultiplier;
    _chromeHeight = height;
    if (!state.supported) {
      return;
    }
    final isFullscreen =
        _fullscreenSupported && await windowChrome.isFullScreen();
    if (previousMultiplier != null && !isFullscreen) {
      await setMultiplier(previousMultiplier);
    } else {
      await _refresh();
    }
  }

  Size _windowSizeForMultiplier(int multiplier) => Size(
    _baseSize.width * multiplier,
    _baseSize.height * multiplier + _chromeHeight,
  );

  Future<void> _refresh() async {
    // ゲスト画面サイズ・ステータスバー表示は最小サイズにも影響するため、
    // フルスクリーン中かどうかに関わらず最新のx1サイズへ更新しておく
    // （フルスクリーン解除後すぐに正しい下限が効くように）。
    await windowScale.setMinimumContentSize(_windowSizeForMultiplier(1));
    if (_fullscreenSupported && await windowChrome.isFullScreen()) {
      // フルスクリーン中は実サイズがどの倍率とも一致しなくなるので、
      // ここで打ち切ってフルスクリーン化直前の状態をそのまま残す。
      return;
    }
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
    if (matched != null && matched != _lastPersistedMultiplier) {
      _lastPersistedMultiplier = matched;
      await preferences.setInt(_multiplierKey, matched);
    }
  }

  /// ウィンドウをゲスト画面の[multiplier]倍へリサイズする。
  Future<void> setMultiplier(int multiplier) async {
    if (!state.supported) {
      return;
    }
    // 最小サイズを先に今のchromeHeightへ合わせておく。Windowsは
    // SetWindowPosによる非対話的なリサイズでも直近のWM_GETMINMAXINFO
    // （最小サイズ）を尊重してリサイズ要求を黙って詰めてしまうため、
    // 縮める方向（ステータスバーを隠す等でchromeHeightが小さくなった
    // 直後）に古い（大きい）最小サイズが残ったままsetContentSizeすると、
    // 要求どおり縮まない（利用者からの報告：「ステータスバーの非表示が
    // 直っていない」）。`_refresh`も同じ最小サイズ設定を行うが、それは
    // リサイズの後になるため間に合わない。
    await windowScale.setMinimumContentSize(_windowSizeForMultiplier(1));
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
    if (state.availableMultipliers.isNotEmpty) {
      // 初期フレームが偶然どれかの倍率と一致していても、保存済みの倍率を
      // 優先する（Linuxはネイティブ側の既定サイズをx1にしてあるため、
      // 一致しただけで保存済みのx2等を無視すると復元されない）。
      final stored = _storedMultiplierAtStartup;
      final target =
          (stored != null && state.availableMultipliers.contains(stored))
          ? stored
          : state.currentMultiplier ?? 1;
      if (target != state.currentMultiplier) {
        await setMultiplier(target);
      }
    }
    await windowScale.show();
  }
}

final windowScaleControllerProvider =
    NotifierProvider<WindowScaleController, WindowScaleState>(
      () => throw UnimplementedError('appがoverrideWithで組み立てる'),
    );
