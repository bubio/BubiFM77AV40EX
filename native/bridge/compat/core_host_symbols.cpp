/*
 * upstream の common.cpp が参照する、ホスト側が用意すべきシンボルの実体。
 *
 * これらは _USE_QT 構成でQtポートが定義しているものだが、
 * 本プロジェクトの _USE_SDL 経路では未定義になる。コアを1行も変更しない
 * 方針のため、実体をブリッジ側で供給する。
 *
 * upstream の get_app_path() は
 *   cpp_homedir + "CommonSourceCodeProject/" + my_procname + "/"
 * を作成し、辞書学習データなどをそこへ書く。既定のままだと
 * ~/CommonSourceCodeProject/ が作られ、design.md 11.3 が定める
 * OS標準領域（macOSなら ~/Library/Application Support/BubiFM77AV40EX/）と
 * 食い違う。そのためホストからの注入を必須とし、注入前に
 * コアがパスを確定しないよう bubi_core_set_home_dir() を用意する。
 * M1で AppDataPaths が返す位置を注入する。
 */
#include <sys/stat.h>
#include <sys/types.h>

#include <cstdlib>
#include <string>

#include "core_host_symbols.h"

std::string cpp_homedir;
std::string my_procname = "BubiFM77AV40EX";

void _my_mkdir(std::string t_dir)
{
	struct stat st;
	if (stat(t_dir.c_str(), &st) != 0) {
		mkdir(t_dir.c_str(), 0700);
	}
}

void bubi_core_set_home_dir(const char* native_path)
{
	if (native_path == nullptr || native_path[0] == '\0') {
		cpp_homedir.clear();
		return;
	}
	cpp_homedir = native_path;
	if (cpp_homedir.back() != '/') {
		cpp_homedir.push_back('/');
	}
}

namespace {

// 明示的な注入がないまま EMU が作られた場合の保険。
// $HOME を無断で汚さないよう、環境変数での上書きを許し、
// 未指定ならカレントディレクトリ配下にする。
struct HomeDirInitializer {
	HomeDirInitializer()
	{
		const char* override_path = std::getenv("BUBI_CORE_HOME");
		bubi_core_set_home_dir(override_path != nullptr ? override_path : ".");
	}
};

const HomeDirInitializer initializer;

} // namespace
