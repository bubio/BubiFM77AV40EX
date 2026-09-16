/*
 * Windows/glibc の <malloc.h> 互換シム。
 *
 * eFM77AV40EXコアの fifo.cpp が <malloc.h> をインクルードするが、
 * macOSにはこのヘッダーがない。コアを変更しない方針のため、
 * 標準の <stdlib.h> へ委譲する本シムをインクルードパスへ置く。
 */
#ifndef BUBI_COMPAT_MALLOC_H_
#define BUBI_COMPAT_MALLOC_H_

#if defined(_MSC_VER) && !defined(__clang__)
// MSVC（cl.exe）は #include_next を持たない。UCRTのincludeディレクトリ
// （.../ucrt）基準の相対指定で実ヘッダーを直接選ぶ。compatディレクトリ
// 基準では ../ucrt/ が存在しないため、本シム自身は再帰的に選ばれない。
#include <../ucrt/malloc.h>
#elif defined(_WIN32) || defined(__linux__)
#include_next <malloc.h>
#else
#include <stdlib.h>
#endif

#endif // BUBI_COMPAT_MALLOC_H_
