/// Flutter公式パッケージが覆わないOSサービス。
///
/// 現状は macOS の security-scoped bookmark だけを扱う。
/// Linux/Windowsの正規化パスとAndroidのSAF永続URI権限は、
/// 担当マイルストーン（M4〜M6）で足す。
library;

export 'src/security_scoped_bookmarks.dart';
