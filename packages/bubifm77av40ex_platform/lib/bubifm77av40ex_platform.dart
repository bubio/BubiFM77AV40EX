/// Flutter公式パッケージが覆わないOSサービス。
///
/// macOSの security-scoped bookmark と、Windows/Linuxのウィンドウ
/// クライアント領域操作、macOS/Linuxのフルスクリーン、Linuxの
/// XDGユーザーディレクトリを扱う。
/// AndroidのSAF永続URI権限は、担当マイルストーン（M7）で足す。
library;

export 'src/full_screen_channel.dart';
export 'src/music_directory.dart';
export 'src/pictures_directory.dart';
export 'src/security_scoped_bookmarks.dart';
export 'src/window_content_size_channel.dart';
