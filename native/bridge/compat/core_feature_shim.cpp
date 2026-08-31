/*
 * BubiCoreFeatureShim の実体。
 *
 * 機種定義は vm/fm7/fm7.h が _FM77AV40EX から導出するため、
 * 判定は必ず同ヘッダーを取り込んだ後に行う。これにより
 * upstream の _MSC_VER 分岐と同じ結果になる。
 */
#include <cstring>

#include "vm/fm7/fm7.h"

#include "core_feature_shim.h"

bool BubiCoreFeatureShim::check_feature(const char* name)
{
	if (name == nullptr) {
		return false;
	}

	// mc6809_base.cpp
	if (std::strcmp(name, "USE_DEBUGGER") == 0) {
#ifdef USE_DEBUGGER
		return true;
#else
		return false;
#endif
	}

	// hd6844.cpp
	if (std::strcmp(name, "_FM77AV40") == 0) {
#if defined(_FM77AV40)
		return true;
#else
		return false;
#endif
	}
	if (std::strcmp(name, "_FM77AV40EX") == 0) {
#if defined(_FM77AV40EX)
		return true;
#else
		return false;
#endif
	}
	if (std::strcmp(name, "_FM77AV40SX") == 0) {
#if defined(_FM77AV40SX)
		return true;
#else
		return false;
#endif
	}

	return false;
}

namespace {
BubiCoreFeatureShim feature_shim;
}

BubiCoreFeatureShim* osd = &feature_shim;
