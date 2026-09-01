import 'package:flutter/services.dart';

/// 利用者が選んだ位置への永続アクセス権。
///
/// macOSでは security-scoped bookmark を作り、次回起動でパスへ戻す。
/// 対応していないOSでは [isSupported] が偽になり、呼び出し側は
/// 正規化したパスをそのまま保存する（design.md 9）。
class SecurityScopedBookmarks {
  const SecurityScopedBookmarks();

  static const MethodChannel _channel = MethodChannel(
    'bubi_fm77av40ex/platform',
  );

  /// このOSでブックマークを扱えるか。
  ///
  /// 実装のないOSではメソッド呼び出しが [MissingPluginException] になるため、
  /// 呼び出し側が事前に分岐できるようにする。
  Future<bool> get isSupported async {
    try {
      await _channel.invokeMethod<String>('resolveBookmark', {'token': ''});
      return true;
    } on MissingPluginException {
      return false;
    }
  }

  /// [path] への永続アクセス権を作り、保存できるトークンを返す。
  Future<String?> create(String path) {
    return _channel.invokeMethod<String>('createBookmark', {'path': path});
  }

  /// 保存したトークンをパスへ戻す。失効していればnullを返す。
  Future<ResolvedBookmark?> resolve(String token) async {
    final resolved = await _channel.invokeMapMethod<String, Object?>(
      'resolveBookmark',
      {'token': token},
    );
    if (resolved == null) {
      return null;
    }
    final path = resolved['path'];
    if (path is! String) {
      return null;
    }
    return ResolvedBookmark(path: path, isStale: resolved['stale'] == true);
  }

  /// アクセスを開始する。使い終わったら必ず [stopAccess] を呼ぶ。
  Future<String?> startAccess(String token) {
    return _channel.invokeMethod<String>('startAccess', {'token': token});
  }

  Future<void> stopAccess(String token) {
    return _channel.invokeMethod<void>('stopAccess', {'token': token});
  }
}

/// OSのファイルマネージャーで場所を開く。
///
/// 利用者が自分でROMを置くフォルダーを案内するために使う。
/// 対応していないOSでは何も起きない。
class FileManagerReveal {
  const FileManagerReveal();

  static const MethodChannel _channel = MethodChannel(
    'bubi_fm77av40ex/platform',
  );

  Future<void> reveal(String path) async {
    try {
      await _channel.invokeMethod<void>('revealInFileManager', {'path': path});
    } on MissingPluginException {
      // 未対応のOSでは案内を出せないだけで、機能そのものは動く。
    }
  }
}

/// [SecurityScopedBookmarks.resolve] の結果。
class ResolvedBookmark {
  const ResolvedBookmark({required this.path, required this.isStale});

  final String path;

  /// 参照先が移動したなどで、ブックマークを作り直したほうがよい状態。
  /// この回のパスは有効である。
  final bool isStale;
}
