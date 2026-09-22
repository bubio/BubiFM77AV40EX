import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:bubifm77av40ex_platform/bubifm77av40ex_platform.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'window_scale.dart';

/// window_manager/screen_retrieverパッケージを使う[WindowScale]
/// （design.md「Window x1/x2/…（M3、APP-04続き）の実装方式」）。
///
/// gamepadsパッケージ採用時（INP-04）と同じく、自前のSwift/C++実装は
/// 増やさず既製パッケージへ委譲するのが原則だが、内容領域（クライアント
/// 領域）のサイズ変更だけはWindowsで例外とする。`window_manager`の
/// `getSize`/`setSize`はWindowsではタイトルバーに加え、見た目には出ない
/// 左右下のリサイズ枠まで含む外形を扱い、これを求める公開APIがない
/// （macOSは`NSWindow.setContentSize:`があるため`window_manager`だけで
/// 足りる）。そのためWindowsだけ[WindowContentSizeChannel]（Win32の
/// `AdjustWindowRectExForDpi`を使う自前実装）へ委譲する（design.md
/// 「x1ウィンドウの大きさの調査」、利用者からの報告：「Windowsでx1が
/// 624x389になる」）。
class OsWindowScale implements WindowScale {
  OsWindowScale({this.windowContentSize = const WindowContentSizeChannel()}) {
    if (_supported) {
      windowManager.addListener(_listener);
      if (Platform.isWindows) {
        // Windowsではネイティブ側のWM_SIZE通知（正確なクライアント領域の
        // サイズ付き）をそのまま公開窓口へ橋渡しする。
        windowContentSize.contentSizeChanges.listen(_controller.add);
      }
    }
  }

  final WindowContentSizeChannel windowContentSize;

  static bool get _supported =>
      Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  final _controller = StreamController<Size>.broadcast();
  late final _listener = _WindowResizeListener(onResized: _emitCurrentSize);

  Future<void> _emitCurrentSize() async {
    if (Platform.isWindows) {
      // Windowsでは[windowContentSize.contentSizeChanges]（ネイティブの
      // WM_SIZE）から直接届くため、window_managerの通知はここでは使わない。
      return;
    }
    _controller.add(await getContentSize());
  }

  @override
  Future<bool> get isSupported async => _supported;

  @override
  Future<Size> getContentSize() {
    if (Platform.isWindows) {
      return windowContentSize.getContentSize();
    }
    return _getContentSizeViaWindowManager();
  }

  // window_managerの`getSize`/`setSize`はウィンドウ全体（タイトルバーを
  // 含む）のフレームを扱うため、タイトルバー分の高さを差し引き・
  // 上乗せして内容領域（映像＋ステータスバー）だけのサイズへ変換する
  // （macOSはタイトルバーだけが枠のため、これで正確な内容領域になる）。
  Future<Size> _getContentSizeViaWindowManager() async {
    final frame = await windowManager.getSize();
    final titleBarHeight = await windowManager.getTitleBarHeight();
    return Size(frame.width, frame.height - titleBarHeight);
  }

  @override
  Future<void> setContentSize(Size size) async {
    if (Platform.isWindows) {
      await windowContentSize.setContentSize(size);
      return;
    }
    final titleBarHeight = await windowManager.getTitleBarHeight();
    await windowManager.setSize(
      Size(size.width, size.height + titleBarHeight),
      animate: true,
    );
  }

  @override
  Future<void> setMinimumContentSize(Size size) async {
    if (Platform.isWindows) {
      await windowContentSize.setMinimumContentSize(size);
      return;
    }
    final titleBarHeight = await windowManager.getTitleBarHeight();
    await windowManager.setMinimumSize(
      Size(size.width, size.height + titleBarHeight),
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
