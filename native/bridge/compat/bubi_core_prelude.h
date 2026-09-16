/*
 * 全翻訳単位へ先頭で強制インクルードするプリアンブル（-include で注入）。
 *
 * eFM77AV40EXコアはMSVC前提で書かれており、標準ヘッダーの一部を
 * 暗黙の推移的インクルードに頼っている。clang/libc++ ではそれらが
 * 届かないため不足分をここで補う。コアのソースは1行も変更しない。
 *
 * real Windows（_WIN32、MSVC/clang-cl/実UCRT）はコアが元々前提とする
 * 環境そのものであるため、この節が補う項目（vswprintfの3引数版、
 * LONG_PTR/ULONG_PTR、min/maxのsize_t版、VK_*マクロ）はUCRT/windows.hが
 * 既に持っており不要かつ再定義で衝突する。Windowsでは
 * cpp_homedir/my_procname/_my_mkdir の宣言（bridge側シンボル、
 * OS非依存）だけを供給し、それ以外はUCRT/windows.h側に委ねる。
 */
#ifndef BUBI_CORE_PRELUDE_H_
#define BUBI_CORE_PRELUDE_H_

#ifdef __cplusplus
#include <climits>   // INT_MAX ほか
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <cwchar>    // vswprintf ほか
#include <cctype>
#include <cwctype>
#include <string>    // std::string / std::wstring
#include <algorithm>
#include <cstdarg>

// コアはキーをwin32仮想キーコードで識別する（例: vm/fm7/keyboard_tables.h）。
// real Windowsでは<windows.h>由来の定義と衝突するため、非Windowsでだけ
// 本シムでVK_*を供給する。
#ifndef _WIN32
#include "vkcodes.h"
#endif

/*
 * upstream の common.cpp には、_WIN32 でも _USE_QT でもない構成
 * （本プロジェクトの _USE_SDL 経路）で次の不足がある。コアを変更できないため、
 * 宣言をここで補い、実体は native/bridge/compat/core_host_symbols.cpp が持つ。
 * これはOSに依存しないbridge側シンボルのため、Windowsでも必要。
 */
extern std::string cpp_homedir;  // 設定・データの基準ディレクトリ
extern std::string my_procname;  // 機種名（アプリデータのサブフォルダー名）
void _my_mkdir(std::string t_dir);

#ifndef _WIN32
/*
 * MSVC の vswprintf は (buffer, format, ap) の3引数だが、POSIX/libc++ は
 * (buffer, count, format, ap) の4引数である。common.cpp の my_swprintf_s は
 * 3引数形で呼ぶため、MSVC互換のオーバーロードを供給する。
 * real WindowsのUCRTは元々この3引数版を持つため不要（かつ再定義で衝突する）。
 */
inline int vswprintf(wchar_t* buffer, const wchar_t* format, va_list ap)
{
	// 呼び出し側 my_swprintf_s は sizeOfBuffer を渡さないため、
	// MSVCの非境界版と同じ意味になる。境界付きの呼び出しは4引数版が選ばれる。
	return ::vswprintf(buffer, static_cast<size_t>(-1), format, ap);
}

// Windows のポインタ幅整数型。common.h の非Windows経路では供給されない。
// real Windowsではbasetsd.h（<windows.h>経由）が既に定義する。
#ifndef LONG_PTR
typedef intptr_t LONG_PTR;
#endif
#ifndef ULONG_PTR
typedef uintptr_t ULONG_PTR;
#endif

/*
 * common.h の min/max は int と unsigned int の組合せしか宣言していない。
 * 64bitホストでは disk.cpp の min(sizeof(...), uint32) が多義になるため、
 * size_t を含む組合せを補う。real Windowsではcommon.hのWindows経路が
 * <algorithm>のstd::min/maxをusingするため不要。
 */
inline size_t min(size_t a, unsigned int b)
{
	return a < static_cast<size_t>(b) ? a : static_cast<size_t>(b);
}

inline size_t min(unsigned int a, size_t b)
{
	return static_cast<size_t>(a) < b ? static_cast<size_t>(a) : b;
}

inline size_t max(size_t a, unsigned int b)
{
	return a > static_cast<size_t>(b) ? a : static_cast<size_t>(b);
}

inline size_t max(unsigned int a, size_t b)
{
	return static_cast<size_t>(a) > b ? static_cast<size_t>(a) : b;
}
#endif // !_WIN32
#else
#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>
#include <ctype.h>
#endif

#endif // BUBI_CORE_PRELUDE_H_
