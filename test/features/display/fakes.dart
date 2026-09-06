import 'dart:async';

import 'package:bubi_fm77av40ex/platform/persistence/window_chrome.dart';

/// [WindowChrome]のFake。既定は対応OS扱いで、`fullScreenChanges`は
/// 呼び出し側が[emit]で任意に流す。
class FakeWindowChrome implements WindowChrome {
  bool supported = true;
  bool currentFullScreen = false;
  final List<bool> setFullScreenCalls = [];

  final StreamController<bool> _changes = StreamController<bool>.broadcast();

  @override
  Future<bool> get isSupported async => supported;

  @override
  Future<bool> isFullScreen() async => currentFullScreen;

  @override
  Future<void> setFullScreen(bool value) async {
    setFullScreenCalls.add(value);
  }

  @override
  Stream<bool> get fullScreenChanges => _changes.stream;

  /// OSからの状態変化を模す。
  void emit(bool value) {
    currentFullScreen = value;
    _changes.add(value);
  }

  Future<void> dispose() => _changes.close();
}
