/*
 * Windows CRT <io.h> の互換シム。
 *
 * eFM77AV40EXコアは common.h などで <io.h> を無条件にインクルードするが、
 * これはWindows専用ヘッダーである。コアを1行も変更しない方針のため、
 * upstreamのソースへ手を入れる代わりに、POSIX側の同等ヘッダーと
 * 名前の異なる関数だけを本シムで提供する。
 *
 * コア自身の src/vm/io.h は常に "io.h" と引用符付きで参照されるため、
 * インクルード元ディレクトリが先に検索され、本シムと衝突しない。
 */
#ifndef BUBI_COMPAT_IO_H_
#define BUBI_COMPAT_IO_H_

#if defined(_WIN32)
#include_next <io.h>
#else

#include <fcntl.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

// _access のモード定数。Windows CRTと同じ値を用いる。
#ifndef F_OK
#define F_OK 0
#endif
#ifndef X_OK
#define X_OK 1
#endif
#ifndef W_OK
#define W_OK 2
#endif
#ifndef R_OK
#define R_OK 4
#endif

#ifdef __cplusplus
extern "C" {
#endif

static inline int _access(const char* path, int mode) { return access(path, mode); }
static inline int _open(const char* path, int flags, int mode) { return open(path, flags, mode); }
static inline int _close(int fd) { return close(fd); }
static inline long _lseek(int fd, long offset, int origin) { return (long)lseek(fd, offset, origin); }
static inline int _read(int fd, void* buffer, unsigned int count) { return (int)read(fd, buffer, count); }
static inline int _write(int fd, const void* buffer, unsigned int count) { return (int)write(fd, buffer, count); }
static inline int _unlink(const char* path) { return unlink(path); }
static inline int _isatty(int fd) { return isatty(fd); }

#ifdef __cplusplus
}
#endif

#endif // _WIN32

#endif // BUBI_COMPAT_IO_H_
