/*
 * Windows向け <pthread.h> 互換シム。
 *
 * eFM77AV40EXコアは _USE_SDL 構成で emu.h から無条件に <pthread.h> を
 * includeするが、Windowsにはこのヘッダーが存在しない。コアを1行も
 * 変更しない方針のため、bridge側（osd/sdl/osd.cpp・osd_sound.cpp）が
 * 実際に使う範囲（再帰ミューテックスのみ。スレッド生成はデバッガー
 * （P2、native/CMakeLists.txtの理由によりdebugger.cppはビルド対象外）
 * だけが使い、ここではコンパイルを通す最小限の宣言だけを供給する）に
 * 限定して、Win32のCRITICAL_SECTIONで実装する。
 */
#ifndef BUBI_COMPAT_PTHREAD_H_
#define BUBI_COMPAT_PTHREAD_H_

#if !defined(_WIN32)
#include_next <pthread.h>
#else

#include <windows.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef CRITICAL_SECTION pthread_mutex_t;
typedef int pthread_mutexattr_t;
typedef unsigned long pthread_t;

#define PTHREAD_MUTEX_RECURSIVE 1

static inline int pthread_mutexattr_init(pthread_mutexattr_t* attr) {
	if (attr != NULL) {
		*attr = 0;
	}
	return 0;
}

static inline int pthread_mutexattr_settype(pthread_mutexattr_t* attr, int type) {
	if (attr != NULL) {
		*attr = type;
	}
	return 0;
}

static inline int pthread_mutexattr_destroy(pthread_mutexattr_t* attr) {
	(void)attr;
	return 0;
}

// Windowsの CRITICAL_SECTION は常に再入可能なため、attr（非再帰指定）は
// このbridgeが必要とする範囲では無視してよい（呼び出し側は常に
// PTHREAD_MUTEX_RECURSIVEを渡す。native/bridge/osd/sdl/osd.cppと
// osd_sound.cppを参照）。
static inline int pthread_mutex_init(pthread_mutex_t* mutex, const pthread_mutexattr_t* attr) {
	(void)attr;
	InitializeCriticalSection(mutex);
	return 0;
}

static inline int pthread_mutex_lock(pthread_mutex_t* mutex) {
	EnterCriticalSection(mutex);
	return 0;
}

static inline int pthread_mutex_unlock(pthread_mutex_t* mutex) {
	LeaveCriticalSection(mutex);
	return 0;
}

static inline int pthread_mutex_destroy(pthread_mutex_t* mutex) {
	DeleteCriticalSection(mutex);
	return 0;
}

#ifdef __cplusplus
}
#endif

#endif // _WIN32

#endif // BUBI_COMPAT_PTHREAD_H_
