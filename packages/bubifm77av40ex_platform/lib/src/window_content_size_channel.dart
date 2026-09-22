import 'package:flutter/services.dart';

/// メインウィンドウのクライアント領域（枠・タイトルバーを除いた中身）を
/// 直接指定・取得するチャンネル（Windows/Linux、design.md「x1ウィンドウの
/// 大きさの調査」）。
///
/// `window_manager`の`setSize`/`getSize`はWindowsではタイトルバーに加え、
/// 見た目には出ない左右下のリサイズ枠まで含む外形を扱い、これを求める
/// 公開APIがない。このチャンネルの裏側（Win32ネイティブ実装）は
/// `AdjustWindowRectExForDpi`でクライアント領域から外形をOSに計算させる
/// ため、呼び出し側はクライアント領域の大きさだけを気にすればよい。
/// Linuxの裏側はFlutterの描画面（FlView）の実際の大きさを扱い、ヘッダー
/// バー等の差はその場で測って足す。
/// macOSは`NSWindow.setContentSize:`にあたる処理を`window_manager`が
/// 内部で行うため、こちらは使わない（[OsWindowScale]がOSで分岐する）。
class WindowContentSizeChannel {
  const WindowContentSizeChannel();

  static const MethodChannel _channel = MethodChannel(
    'bubifm77av40ex/platform/window_scale',
  );
  static const EventChannel _changes = EventChannel(
    'bubifm77av40ex/platform/window_scale/changes',
  );

  /// このOSで実装があるか。
  ///
  /// 実装のないOSでは[MissingPluginException]になるため、呼び出し側が
  /// 事前に分岐できるようにする（`FullScreenChannel.isSupported`と同じ形）。
  Future<bool> get isSupported async {
    try {
      await _channel.invokeMethod<List<Object?>>('getContentSize');
      return true;
    } on MissingPluginException {
      return false;
    }
  }

  /// 現在のクライアント領域のサイズ（論理px）。
  Future<Size> getContentSize() async {
    final result = await _channel.invokeMethod<List<Object?>>('getContentSize');
    return _toSize(result);
  }

  /// クライアント領域のサイズを変える（論理px）。ウィンドウの位置は保つ。
  Future<void> setContentSize(Size size) {
    return _channel.invokeMethod<void>('setContentSize', {
      'width': size.width,
      'height': size.height,
    });
  }

  /// クライアント領域の最小サイズを設定する（論理px）。
  Future<void> setMinimumContentSize(Size size) {
    return _channel.invokeMethod<void>('setMinimumContentSize', {
      'width': size.width,
      'height': size.height,
    });
  }

  /// クライアント領域のサイズの変化（OS操作によるドラッグリサイズを含む）。
  Stream<Size> get contentSizeChanges {
    return _changes.receiveBroadcastStream().map(
      (event) => _toSize(event as List<Object?>),
    );
  }

  Size _toSize(List<Object?>? value) {
    final list = value!;
    return Size((list[0]! as num).toDouble(), (list[1]! as num).toDouble());
  }
}
