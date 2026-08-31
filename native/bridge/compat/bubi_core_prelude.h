/*
 * 全翻訳単位へ先頭で強制インクルードするプリアンブル（-include で注入）。
 *
 * eFM77AV40EXコアはMSVC前提で書かれており、標準ヘッダーの一部を
 * 暗黙の推移的インクルードに頼っている。clang/libc++ ではそれらが
 * 届かないため不足分をここで補う。コアのソースは1行も変更しない。
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
// <windows.h> の代わりに必要な定義だけを供給する。
#include "vkcodes.h"

/*
 * upstream の common.cpp には、_WIN32 でも _USE_QT でもない構成
 * （本プロジェクトの _USE_SDL 経路）で次の不足がある。コアを変更できないため、
 * 宣言をここで補い、実体は native/bridge/compat/core_host_symbols.cpp が持つ。
 */
#include <string>
extern std::string cpp_homedir;  // 設定・データの基準ディレクトリ
extern std::string my_procname;  // 機種名（アプリデータのサブフォルダー名）
void _my_mkdir(std::string t_dir);

/*
 * MSVC の vswprintf は (buffer, format, ap) の3引数だが、POSIX/libc++ は
 * (buffer, count, format, ap) の4引数である。common.cpp の my_swprintf_s は
 * 3引数形で呼ぶため、MSVC互換のオーバーロードを供給する。
 */
inline int vswprintf(wchar_t* buffer, const wchar_t* format, va_list ap)
{
	// 呼び出し側 my_swprintf_s は sizeOfBuffer を渡さないため、
	// MSVCの非境界版と同じ意味になる。境界付きの呼び出しは4引数版が選ばれる。
	return ::vswprintf(buffer, static_cast<size_t>(-1), format, ap);
}

// Windows のポインタ幅整数型。common.h の非Windows経路では供給されない。
#ifndef LONG_PTR
typedef intptr_t LONG_PTR;
#endif
#ifndef ULONG_PTR
typedef uintptr_t ULONG_PTR;
#endif

/*
 * common.h の min/max は int と unsigned int の組合せしか宣言していない。
 * 64bitホストでは disk.cpp の min(sizeof(...), uint32) が多義になるため、
 * size_t を含む組合せを補う。
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
