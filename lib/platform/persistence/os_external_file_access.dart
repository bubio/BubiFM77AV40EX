import 'dart:io';

import 'package:bubi_fm77av40ex_platform/bubi_fm77av40ex_platform.dart';
import 'package:file_selector/file_selector.dart' as selector;

import 'external_file_access.dart';

/// OSのダイアログと永続アクセス権を使う [ExternalFileAccess]。
///
/// macOSでは security-scoped bookmark をトークンとして保存する。
/// ブックマークを扱えないOSでは正規化した絶対パスをトークンにする
/// （design.md 9）。どちらの場合も原本は利用者の位置に置いたままにする。
class OsExternalFileAccess implements ExternalFileAccess {
  OsExternalFileAccess({SecurityScopedBookmarks? bookmarks})
    : _bookmarks = bookmarks ?? const SecurityScopedBookmarks();

  final SecurityScopedBookmarks _bookmarks;
  bool? _bookmarksSupported;

  Future<bool> _supportsBookmarks() async {
    return _bookmarksSupported ??= await _bookmarks.isSupported;
  }

  @override
  Future<ExternalResource?> pickDirectory({String? dialogTitle}) async {
    final path = await selector.getDirectoryPath(
      confirmButtonText: dialogTitle,
    );
    if (path == null) {
      return null;
    }
    return _resourceFor(path);
  }

  @override
  Future<ExternalResource?> pickFile({
    String? dialogTitle,
    List<String> allowedExtensions = const [],
  }) async {
    final file = await selector.openFile(
      confirmButtonText: dialogTitle,
      acceptedTypeGroups: allowedExtensions.isEmpty
          ? const []
          : [selector.XTypeGroup(extensions: allowedExtensions)],
    );
    if (file == null) {
      return null;
    }
    return _resourceFor(file.path);
  }

  @override
  Future<ExternalResource?> pickSaveLocation({
    String? dialogTitle,
    String? suggestedFileName,
  }) async {
    final location = await selector.getSaveLocation(
      confirmButtonText: dialogTitle,
      suggestedName: suggestedFileName,
    );
    if (location == null) {
      return null;
    }
    return _resourceFor(location.path);
  }

  @override
  Future<ExternalResource?> resolve(String token) async {
    if (await _supportsBookmarks()) {
      ResolvedBookmark? resolved;
      try {
        resolved = await _bookmarks.resolve(token);
      } on Object {
        resolved = null;
      }
      if (resolved == null) {
        return null; // 失効。呼び出し側は選び直しを促す。
      }
      return _BookmarkResource(
        token: token,
        path: resolved.path,
        bookmarks: _bookmarks,
      );
    }
    if (!_existsAt(token)) {
      return null;
    }
    return _PathResource(token);
  }

  Future<ExternalResource> _resourceFor(String path) async {
    if (await _supportsBookmarks()) {
      String? token;
      try {
        token = await _bookmarks.create(path);
      } on Object {
        // App Sandboxを有効にしていない環境では `.withSecurityScope` 付きの
        // ブックマークを作れないことがある（design.md 16.1）。
        // その回の操作は続けられ、再起動後に選び直しが要るだけである。
        token = null;
      }
      if (token != null) {
        return _BookmarkResource(
          token: token,
          path: path,
          bookmarks: _bookmarks,
        );
      }
    }
    return _PathResource(path);
  }
}

bool _existsAt(String path) =>
    FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;

/// security-scoped bookmark を持つリソース。
class _BookmarkResource implements ExternalResource {
  _BookmarkResource({
    required this.token,
    required this.path,
    required this.bookmarks,
  });

  @override
  final String token;

  final String path;
  final SecurityScopedBookmarks bookmarks;

  @override
  String get displayName => _displayNameOf(path);

  @override
  Future<T> withAccess<T>(Future<T> Function(String nativePath) body) async {
    final scopedPath = await bookmarks.startAccess(token) ?? path;
    try {
      return await body(scopedPath);
    } finally {
      await bookmarks.stopAccess(token);
    }
  }

  @override
  Future<void> release() => bookmarks.stopAccess(token);
}

/// 正規化パスだけを持つリソース。ブックマークのないOS向け。
class _PathResource implements ExternalResource {
  _PathResource(this.token);

  @override
  final String token;

  @override
  String get displayName => _displayNameOf(token);

  @override
  Future<T> withAccess<T>(Future<T> Function(String nativePath) body) =>
      body(token);

  @override
  Future<void> release() async {}
}

/// 表示用の名前。フルパスは通常ログへ残さない（NFR-07）。
String _displayNameOf(String path) {
  final normalized = path.endsWith(Platform.pathSeparator)
      ? path.substring(0, path.length - 1)
      : path;
  final index = normalized.lastIndexOf(Platform.pathSeparator);
  return index < 0 ? normalized : normalized.substring(index + 1);
}
