import 'package:flutter/services.dart';

/// メインウィンドウのフルスクリーン状態（VID-03）。
///
/// OS標準の操作（緑ボタン、標準ショートカット）でも状態が変わるため、
/// 一方向のコマンドだけでなく、変化を通知する[fullScreenChanges]を持つ。
class FullScreenChannel {
  const FullScreenChannel();

  static const MethodChannel _channel = MethodChannel(
    'bubi_fm77av40ex/platform',
  );
  static const EventChannel _fullScreenEvents = EventChannel(
    'bubi_fm77av40ex/platform/fullscreen',
  );

  /// このOSでフルスクリーン制御を扱えるか。
  ///
  /// 実装のないOSではメソッド呼び出しが[MissingPluginException]になるため、
  /// 呼び出し側が事前に分岐できるようにする
  /// （`SecurityScopedBookmarks.isSupported`と同じ形）。
  Future<bool> get isSupported async {
    try {
      await _channel.invokeMethod<bool>('isFullScreen');
      return true;
    } on MissingPluginException {
      return false;
    }
  }

  /// 現在メインウィンドウがフルスクリーンかどうか。
  Future<bool> isFullScreen() async {
    final value = await _channel.invokeMethod<bool>('isFullScreen');
    return value ?? false;
  }

  /// フルスクリーンを切り替える。
  ///
  /// 実際の状態反映は[fullScreenChanges]の通知を待つ
  /// （design.md 12.3「チェック項目はコマンド完了後の実状態を表示する」）。
  Future<void> setFullScreen(bool value) {
    return _channel.invokeMethod<void>('setFullScreen', {'value': value});
  }

  /// フルスクリーン状態の変化（OS操作による変化を含む）。
  Stream<bool> get fullScreenChanges {
    return _fullScreenEvents.receiveBroadcastStream().map(
      (event) => event as bool,
    );
  }
}
