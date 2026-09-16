/*
 * Windows向け <dirent.h> 互換シム。
 *
 * このヘッダーはbridge自身のコード（native/bridge/src/bubi_fm77av.cpp）が
 * ROM/coreディレクトリを列挙するために使うPOSIX API（opendir/readdir/
 * closedir、struct dirent、DIR）を、Win32のFindFirstFile系で実装する。
 * upstreamコアはこのヘッダーをincludeしない（無改変方針とは無関係）。
 * 非Windowsでは本物の<dirent.h>へ委譲する。
 */
#ifndef BUBI_COMPAT_DIRENT_H_
#define BUBI_COMPAT_DIRENT_H_

#if !defined(_WIN32)
#include_next <dirent.h>
#else

#include <windows.h>
#include <cstring>
#include <string>

#ifdef __cplusplus
extern "C" {
#endif

struct dirent {
	char d_name[MAX_PATH];
};

typedef struct DIR {
	HANDLE handle;
	WIN32_FIND_DATAA find_data;
	bool has_pending;
	struct dirent entry;
} DIR;

static inline DIR* opendir(const char* path) {
	std::string pattern(path);
	if (pattern.empty()) {
		return nullptr;
	}
	if (pattern.back() != '\\' && pattern.back() != '/') {
		pattern += '\\';
	}
	pattern += '*';

	DIR* dir = new DIR();
	dir->handle = FindFirstFileA(pattern.c_str(), &dir->find_data);
	if (dir->handle == INVALID_HANDLE_VALUE) {
		delete dir;
		return nullptr;
	}
	dir->has_pending = true;
	return dir;
}

static inline struct dirent* readdir(DIR* dir) {
	if (dir == nullptr) {
		return nullptr;
	}
	if (!dir->has_pending) {
		if (!FindNextFileA(dir->handle, &dir->find_data)) {
			return nullptr;
		}
	}
	dir->has_pending = false;
	std::strncpy(dir->entry.d_name, dir->find_data.cFileName, MAX_PATH - 1);
	dir->entry.d_name[MAX_PATH - 1] = '\0';
	return &dir->entry;
}

static inline int closedir(DIR* dir) {
	if (dir == nullptr) {
		return -1;
	}
	FindClose(dir->handle);
	delete dir;
	return 0;
}

#ifdef __cplusplus
}
#endif

#endif // _WIN32

#endif // BUBI_COMPAT_DIRENT_H_
