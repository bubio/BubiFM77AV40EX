import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/persistence/app_data_paths.dart';

/// [EmulatorView]が`RepaintBoundary`へ渡す共有key。
///
/// スクリーンショット（VID-05）はWidget外（メニューのコールバック）から
/// トリガーされるため、キャプチャ対象のRenderObjectをこのkey経由で探す。
final screenshotBoundaryKeyProvider = Provider<GlobalKey>((ref) => GlobalKey());

/// [ScreenshotService.capture]が失敗したときの例外。
class ScreenshotException implements Exception {
  ScreenshotException(this.message);

  final String message;

  @override
  String toString() => 'ScreenshotException: $message';
}

/// エミュレーター画面を画像として保存する（VID-05）。
///
/// design.md 11.4「デスクトップのスクリーンショットと録音はPictures/Music
/// 配下のアプリフォルダーを既定候補とし…」の通り、保存ダイアログを出さず
/// 直接書き出す。design.md 6「初期実装は表示結果を保存する」の通り、
/// フィルター適用後の見た目（`RepaintBoundary`が包む範囲）をそのまま
/// 保存する。ファイルI/Oは[AppDataPaths]経由に限り、`dart:io`へ直接
/// 触れない（design.md 3.1、11.2）。
class ScreenshotService {
  const ScreenshotService({required this.appDataPaths});

  final AppDataPaths appDataPaths;

  /// [key]が指す`RepaintBoundary`の現在の内容をPNGとして保存し、
  /// 保存先のOSパスを返す。
  Future<String> capture(GlobalKey key) async {
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderRepaintBoundary) {
      throw ScreenshotException('画面が見つかりません。');
    }
    final fileName = 'BubiFM77AV40EX-${_timestamp()}.png';
    final location = await appDataPaths.pictureFile(fileName);
    if (location == null) {
      throw ScreenshotException('保存先を取得できません。');
    }
    final image = await renderObject.toImage();
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw ScreenshotException('画像を書き出せません。');
    }
    await location.writeAtomic(byteData.buffer.asUint8List());
    return location.nativePath;
  }

  String _timestamp() {
    final now = DateTime.now();
    String pad(int value, [int width = 2]) =>
        value.toString().padLeft(width, '0');
    return '${now.year}${pad(now.month)}${pad(now.day)}-'
        '${pad(now.hour)}${pad(now.minute)}${pad(now.second)}';
  }
}

/// `app`が[ScreenshotService]の実体を差し込む（design.md 3.1）。
final screenshotServiceProvider = Provider<ScreenshotService>(
  (ref) => throw UnimplementedError('appがoverrideWithValueで組み立てる'),
);
