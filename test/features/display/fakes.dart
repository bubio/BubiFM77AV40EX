import 'dart:async';
import 'dart:ui';

import 'package:bubi_fm77av40ex/platform/persistence/window_chrome.dart';
import 'package:bubi_fm77av40ex/platform/persistence/window_scale.dart';

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

/// [WindowScale]のFake。既定は対応OS扱い、主ディスプレイの作業領域は
/// 1920x1080論理pxとする。
class FakeWindowScale implements WindowScale {
  bool supported = true;
  Size displaySize = const Size(1920, 1080);
  Size contentSize = const Size(640, 400);
  final List<Size> setContentSizeCalls = [];
  int showCalls = 0;

  final StreamController<Size> _changes = StreamController<Size>.broadcast();

  @override
  Future<bool> get isSupported async => supported;

  @override
  Future<Size> getContentSize() async => contentSize;

  @override
  Future<void> setContentSize(Size size) async {
    setContentSizeCalls.add(size);
    contentSize = size;
  }

  @override
  Future<Size> getAvailableDisplaySize() async => displaySize;

  @override
  Stream<Size> get contentSizeChanges => _changes.stream;

  @override
  Future<void> show() async {
    showCalls++;
  }

  /// OS側（ドラッグ操作等）でのリサイズを模す。
  void emit(Size size) {
    contentSize = size;
    _changes.add(size);
  }

  Future<void> dispose() => _changes.close();
}
