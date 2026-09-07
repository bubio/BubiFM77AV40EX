import 'dart:io';

import 'package:bubi_fm77av40ex/features/display/screenshot_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../session/fakes.dart';

void main() {
  late Directory tempDir;
  late FakeAppDataPaths appDataPaths;
  late ScreenshotService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('screenshot_test');
    appDataPaths = FakeAppDataPaths()..picturesPath = tempDir.path;
    service = ScreenshotService(appDataPaths: appDataPaths);
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  // `RenderRepaintBoundary.toImage()`の実際のラスタライズは`flutter test`の
  // software rendererでは安定して完了しない（ハング）ため、ここでは
  // 境界・保存先が欠けている異常系だけを自動検証する。実際にPNGが書き出
  // されることはmacOS実機でのメニュー操作で確認する
  // （development_plan.md「表示」進捗の未実施）。
  testWidgets('境界が見つからなければScreenshotExceptionを投げる', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: Container(key: key)));

    expect(() => service.capture(key), throwsA(isA<ScreenshotException>()));
  });

  testWidgets('captureBytesも境界が見つからなければScreenshotExceptionを投げる'
      '（STA-01のサムネイル取得と共有する経路）', (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(home: Container(key: key)));

    expect(
      () => service.captureBytes(key),
      throwsA(isA<ScreenshotException>()),
    );
  });

  testWidgets('保存先が取得できなければScreenshotExceptionを投げる', (tester) async {
    appDataPaths.picturesPath = null;
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: Container(color: Colors.blue, width: 10, height: 10),
        ),
      ),
    );

    expect(() => service.capture(key), throwsA(isA<ScreenshotException>()));
  });
}
