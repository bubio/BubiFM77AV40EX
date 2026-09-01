/// コアの画面をFlutterの`Texture`へ渡すための橋渡し。
///
/// `package:flutter`（`dart:ui`）に依存するため、FFIだけの検証
/// （`tool/native_ffi_check.dart`）が読み込むメインバレル
/// `bubi_fm77av40ex_core.dart`とは別に公開する。Flutterエンジンが
/// あるアプリ側（`lib/app/`）だけがこのエントリーポイントを使う。
library;

export 'src/video_texture.dart';
