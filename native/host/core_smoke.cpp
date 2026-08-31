/*
 * 最小ホストプログラム（development_plan.md 5.2）。
 *
 * eFM77AV40EXコアを無改変のままリンクし、
 *   1. EMU/VM を生成できる
 *   2. リセットできる
 *   3. ROMが1つもない状態で一定フレーム実行しても異常終了しない
 *   4. 破棄でき、生成と破棄を繰り返せる
 * ことだけを確認する。映像・音声・入力は接続しない。
 * C ABI、Core thread、Texture、音声はM0 5.3の技術検証ゲート以降で扱う。
 *
 * 実行は一定フレーム分行う。ここを通さないと、ブリッジが供給する
 * check_feature（機種判定とUSE_DEBUGGER）や min/max のオーバーロードが
 * 実行経路として検証されないため。
 */
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "emu.h"

#include "core_host_symbols.h"

namespace {

// 生成と破棄を繰り返し、2周目以降で落ちないことを見る。
constexpr int kCycles = 3;

// 約1秒分。ROMがないためCPUは0を読み続けるが、実行経路自体は通る。
constexpr int kFrames = 60;

int run_cycle(int index, const char* home_dir)
{
	// コアがアプリケーションデータを置く場所は必ずホストが決める。
	// 既定のままだと ~/CommonSourceCodeProject/ が作られてしまう。
	bubi_core_set_home_dir(home_dir);

	EMU* emu = new EMU();
	if (emu == nullptr) {
		std::fprintf(stderr, "cycle %d: EMU allocation failed\n", index);
		return 1;
	}

	VM_TEMPLATE* vm = emu->get_vm();
	if (vm == nullptr) {
		std::fprintf(stderr, "cycle %d: VM was not constructed\n", index);
		delete emu;
		return 1;
	}

	const double frame_rate = vm->get_frame_rate();
	// FM77AV40EXの基準は約59.94fps（specification.md 5章）。
	if (!(frame_rate > 50.0 && frame_rate < 70.0)) {
		std::fprintf(stderr, "cycle %d: unexpected frame rate %f\n", index, frame_rate);
		delete emu;
		return 1;
	}

	// ROMがなくてもリセットと実行で異常終了しないことを確認する。
	vm->reset();
	for (int frame = 0; frame < kFrames; ++frame) {
		vm->run();
	}
	vm->special_reset();
	vm->run();

	delete emu;
	std::printf("cycle %d: ok (frame rate %.2f, %d frames)\n", index, frame_rate, kFrames);
	return 0;
}

} // namespace

int main(int argc, char* argv[])
{
	// 検証中にホームディレクトリを汚さないよう、書込み先を明示的に受け取る。
	const char* home_dir = (argc > 1) ? argv[1] : ".";

	for (int i = 0; i < kCycles; ++i) {
		if (run_cycle(i, home_dir) != 0) {
			return EXIT_FAILURE;
		}
	}
	std::printf("core smoke test passed (%d cycles)\n", kCycles);
	return EXIT_SUCCESS;
}
