/*
 * Windows向け <strings.h> 互換シム。
 *
 * bridge自身のコード（native/bridge/src/bubi_fm77av.cpp）が大文字小文字を
 * 無視した文字列比較（strcasecmp/strncasecmp）に使うPOSIXヘッダーだが、
 * WindowsのUCRTには存在しない。UCRTの同等関数（_stricmp/_strnicmp）へ
 * 委譲する。非Windowsでは本物の<strings.h>へ委譲する。
 */
#ifndef BUBI_COMPAT_STRINGS_H_
#define BUBI_COMPAT_STRINGS_H_

#if !defined(_WIN32)
#include_next <strings.h>
#else

#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

static inline int strcasecmp(const char* a, const char* b) {
	return _stricmp(a, b);
}

static inline int strncasecmp(const char* a, const char* b, size_t n) {
	return _strnicmp(a, b, n);
}

#ifdef __cplusplus
}
#endif

#endif // _WIN32

#endif // BUBI_COMPAT_STRINGS_H_
