/*
 * Windows/glibc の <malloc.h> 互換シム。
 *
 * eFM77AV40EXコアの fifo.cpp が <malloc.h> をインクルードするが、
 * macOSにはこのヘッダーがない。コアを変更しない方針のため、
 * 標準の <stdlib.h> へ委譲する本シムをインクルードパスへ置く。
 */
#ifndef BUBI_COMPAT_MALLOC_H_
#define BUBI_COMPAT_MALLOC_H_

#if defined(_WIN32) || defined(__linux__)
#include_next <malloc.h>
#else
#include <stdlib.h>
#endif

#endif // BUBI_COMPAT_MALLOC_H_
