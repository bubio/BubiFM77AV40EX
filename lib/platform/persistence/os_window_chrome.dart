import 'package:bubi_fm77av40ex_platform/bubi_fm77av40ex_platform.dart';

import 'window_chrome.dart';

/// OSのフルスクリーンチャンネルを使う[WindowChrome]（design.md 3.1）。
class OsWindowChrome implements WindowChrome {
  OsWindowChrome({this.channel = const FullScreenChannel()});

  final FullScreenChannel channel;

  @override
  Future<bool> get isSupported => channel.isSupported;

  @override
  Future<bool> isFullScreen() => channel.isFullScreen();

  @override
  Future<void> setFullScreen(bool value) => channel.setFullScreen(value);

  @override
  Stream<bool> get fullScreenChanges => channel.fullScreenChanges;
}
