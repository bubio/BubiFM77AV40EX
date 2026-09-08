import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'window_scale.dart';

/// window_manager/screen_retrieverパッケージを使う[WindowScale]
/// （design.md「Window x1/x2/…（M3、APP-04続き）の実装方式」）。
///
/// gamepadsパッケージ採用時（INP-04）と同じく、自前のSwift/C++実装は
/// 増やさず既製パッケージへ委譲する。
class OsWindowScale implements WindowScale {
  OsWindowScale() {
    if (_supported) {
      windowManager.addListener(_listener);
    }
  }

  static bool get _supported =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  final _controller = StreamController<Size>.broadcast();
  late final _listener = _WindowResizeListener(onResized: _emitCurrentSize);

  Future<void> _emitCurrentSize() async {
    _controller.add(await getContentSize());
  }

  @override
  Future<bool> get isSupported async => _supported;

  // window_managerの`getSize`/`setSize`はウィンドウ全体（タイトルバーを
  // 含む）のフレームを扱うため、タイトルバー分の高さを差し引き・
  // 上乗せして内容領域（映像＋ステータスバー）だけのサイズへ変換する。
  @override
  Future<Size> getContentSize() async {
    final frame = await windowManager.getSize();
    final titleBarHeight = await windowManager.getTitleBarHeight();
    return Size(frame.width, frame.height - titleBarHeight);
  }

  @override
  Future<void> setContentSize(Size size) async {
    final titleBarHeight = await windowManager.getTitleBarHeight();
    await windowManager.setSize(
      Size(size.width, size.height + titleBarHeight),
      animate: true,
    );
  }

  @override
  Future<Size> getAvailableDisplaySize() async {
    final display = await screenRetriever.getPrimaryDisplay();
    return display.visibleSize ?? display.size;
  }

  @override
  Stream<Size> get contentSizeChanges => _controller.stream;

  @override
  Future<void> show() => windowManager.show();
}

class _WindowResizeListener with WindowListener {
  _WindowResizeListener({required this.onResized});

  final Future<void> Function() onResized;

  @override
  void onWindowResized() {
    unawaited(onResized());
  }
}
