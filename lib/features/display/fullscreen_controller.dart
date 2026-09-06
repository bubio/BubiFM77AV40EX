import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/persistence/window_chrome.dart';

/// フルスクリーン状態（VID-03）。
///
/// [supported]が偽のOSでは[isFullscreen]は常に偽で、メニューは無効化する。
typedef FullscreenState = ({bool isFullscreen, bool supported});

const _unsupportedFullscreenState = (isFullscreen: false, supported: false);

/// メインウィンドウのフルスクリーン状態を扱う（VID-03）。
///
/// OS操作（緑ボタン、標準ショートカット）でも変わるため、[setFullscreen]は
/// コマンドを送るだけで、実際の状態反映は[WindowChrome.fullScreenChanges]
/// の通知を待つ（design.md 12.3「チェック項目はコマンド完了後の実状態を
/// 表示する」）。
class FullscreenController extends Notifier<FullscreenState> {
  FullscreenController({required this.windowChrome});

  final WindowChrome windowChrome;

  StreamSubscription<bool>? _subscription;

  @override
  FullscreenState build() {
    ref.onDispose(() {
      unawaited(_subscription?.cancel());
    });
    unawaited(_initialize());
    return _unsupportedFullscreenState;
  }

  Future<void> _initialize() async {
    if (!await windowChrome.isSupported) {
      return;
    }
    final initial = await windowChrome.isFullScreen();
    state = (isFullscreen: initial, supported: true);
    _subscription = windowChrome.fullScreenChanges.listen((value) {
      state = (isFullscreen: value, supported: true);
    });
  }

  /// フルスクリーンを切り替える。未対応のOSでは何もしない。
  Future<void> setFullscreen(bool value) async {
    if (!state.supported) {
      return;
    }
    await windowChrome.setFullScreen(value);
  }
}

final fullscreenControllerProvider =
    NotifierProvider<FullscreenController, FullscreenState>(
      () => throw UnimplementedError('appがoverrideWithで組み立てる'),
    );
