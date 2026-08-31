/*
 * コアが要求するホスト側シンボルの注入口。
 *
 * 詳細は core_host_symbols.cpp のコメントを参照。
 */
#ifndef BUBI_CORE_HOST_SYMBOLS_H_
#define BUBI_CORE_HOST_SYMBOLS_H_

/// コアがアプリケーションデータを置く基準ディレクトリを設定する。
///
/// upstream は初回の get_app_path() でパスを確定させるため、
/// EMU を生成する前に呼ぶこと。design.md 11.2 の AppDataPaths が
/// 返す位置を渡す。
void bubi_core_set_home_dir(const char* native_path);

#endif // BUBI_CORE_HOST_SYMBOLS_H_
