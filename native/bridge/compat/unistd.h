/*
 * Windows向け <unistd.h> 互換シム。
 *
 * bridge自身のコード（native/bridge/src/bubi_fm77av.cpp）がunlink()に
 * 使うPOSIXヘッダーだが、WindowsのUCRTには存在しない。UCRTの同等関数
 * （_unlink、<io.h>由来）へ委譲する。非Windowsでは本物の<unistd.h>へ
 * 委譲する。
 */
#ifndef BUBI_COMPAT_UNISTD_H_
#define BUBI_COMPAT_UNISTD_H_

#if !defined(_WIN32)
#include_next <unistd.h>
#else

#include <io.h>
#include <direct.h>

#ifdef __cplusplus
extern "C" {
#endif

static inline int unlink(const char* path) {
	return _unlink(path);
}

#ifdef __cplusplus
}

// テストコード（native/host/*.cpp）がPOSIXの mkdir(path, mode) 形で
// 呼ぶための互換。modeはWindowsに相当概念がないため無視する。
// UCRTの<direct.h>が1引数の mkdir を extern "C" で宣言しており、
// extern "C" 同士はオーバーロードできないため、C++リンケージで定義する。
inline int mkdir(const char* path, int mode) {
	(void)mode;
	return _mkdir(path);
}
#endif

#endif // _WIN32

#endif // BUBI_COMPAT_UNISTD_H_
