/*
 * EMU のデバッガー関連メソッドのスタブ。
 *
 * upstream の src/debugger.cpp は OSD_SDL 経路でコンパイルできない。
 * EMU::debugger_thread_id が int として宣言される一方、pthread_create へ
 * pthread_t* として渡すためである（native/CMakeLists.txt のコメント参照）。
 *
 * デバッガーはP2機能（DBG-01/DBG-02）であり、M0〜M1では提供しない。
 * ここでは EMU が参照する最小限のメソッドだけを無効動作で定義し、
 * コアと最小ホストがリンクできる状態にする。
 *
 * P2着手時にこのファイルを削除し、コアを変更しない形で
 * src/debugger.cpp を有効化する方法を技術検証する。
 */
#include "emu.h"

#ifdef USE_DEBUGGER

void EMU::initialize_debugger()
{
	now_debugging = false;
	now_waiting_in_debugger = false;
}

void EMU::release_debugger()
{
	now_debugging = false;
	now_waiting_in_debugger = false;
}

void EMU::close_debugger()
{
	now_debugging = false;
}

bool EMU::is_debugger_enabled(int cpu_index)
{
	// デバッガー未提供のため、どのCPUについても無効を返す。
	return false;
}

void EMU::start_waiting_in_debugger()
{
}

void EMU::finish_waiting_in_debugger()
{
}

void EMU::process_waiting_in_debugger()
{
}

#endif // USE_DEBUGGER
