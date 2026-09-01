/*
 * M0 5.3 音声ゲートのspike。
 *
 * 検証すること:
 *   1. `vm->create_sound()` は `vm->run()` が1フレームぶん生成した分を
 *      「取り出すだけ」にできる。`sound_samples` を1フレーム分の
 *      サンプル数に合わせれば、内部の `drive()` による追加進行
 *      （`extra_frames`）はほぼ0で済む。
 *
 *      これが重要な理由: `VM::run()` は `event->drive()` そのものであり
 *      （vm/fm7/fm7.cpp）、`EVENT::create_sound()` は音声バッファが
 *      足りなければ内部で追加の `drive()` を呼ぶ（vm/event.cpp）。
 *      このブリッジのCore threadは壁時計で `vm->run()` を1フレーム/tickの
 *      ペースで呼ぶ（bubi_fm77av.cpp）。もし `create_sound()` を
 *      毎tick単純に呼び足すと、`sound_samples` が1フレーム分より大きい
 *      限りバッファが不足するたびに `drive()` が追加で走り、映像用の
 *      `vm->run()` と二重にVMを進めてしまう。実時間より速く進む失敗モードは
 *      フレームバッファや音声の有無だけを見るスモークテストでは見つからない
 *      （native/bridge/osd/sdl/osd_sound.cpp の元コメントが、別プロジェクト
 *      由来ながら機構としては正しく指摘していた点）。
 *
 *   2. PCMリングは読み手が追いつかない（アンダーラン）／書き手が
 *      追いつかない（オーバーラン）のどちらでも、無音埋めと最古破棄で
 *      安全に吸収できる。
 *
 * 検出器そのものの妥当性を確かめるため、わざと `sound_samples` を
 * 1フレーム分より大きくして `extra_frames` が積み上がることも確認する
 * （frame_ringのspikeで面を2枚に減らして破断を再現したのと同じ考え方）。
 *
 * 結論は docs/dev/design.md 16.1 へ記録し、このディレクトリごと削除して
 * WP4で製品コードへ作り直す。
 */
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <vector>

#include "core_host_symbols.h"
#include "emu.h"

#include "pcm_ring.h"

namespace {

// sound_frequency_table[6]（emu.cpp）。M1 WP4もこれを既定にする。
constexpr int kSoundRate = 48000;

struct PacingResult {
	uint64_t total_extra_frames = 0;
};

// [frame_count]フレームぶん vm->run() を進め、毎回 create_sound() を
// 呼んでPCMをringへ供給する。extra_framesの累計を返す。
PacingResult drive_and_capture(VM_TEMPLATE* vm, int sound_samples, int frame_count,
                                bubi_spike::PcmRing* ring)
{
	PacingResult result;
	for (int frame = 0; frame < frame_count; ++frame) {
		vm->run();
		int extra_frames = 0;
		uint16_t* pcm = vm->create_sound(&extra_frames);
		result.total_extra_frames += static_cast<uint64_t>(extra_frames);
		if (ring != nullptr && pcm != nullptr) {
			// コアが返すのは符号ありint16のビット列（osd_sound.cppの
			// (int16_t*)キャストと同じ扱い）。
			const int16_t* signed_pcm = reinterpret_cast<const int16_t*>(pcm);
			ring->push(signed_pcm, static_cast<std::size_t>(sound_samples));
		}
	}
	return result;
}

bool check(bool condition, const char* what)
{
	std::printf("%s: %s\n", condition ? "OK" : "NG", what);
	return condition;
}

} // namespace

int main(int argc, char** argv)
{
	const char* home_dir = (argc > 1) ? argv[1] : ".";
	bubi_core_set_home_dir(home_dir);

	bool all_ok = true;

	// --- 1. 正しい設定: sound_samples を1フレーム分に合わせる ---
	{
		EMU* emu = new EMU();
		VM_TEMPLATE* vm = emu->get_vm();
		const double frame_rate = vm->get_frame_rate();
		const int samples_per_frame =
			static_cast<int>(std::lround(kSoundRate / frame_rate));
		vm->initialize_sound(kSoundRate, samples_per_frame);

		bubi_spike::PcmRing ring(static_cast<std::size_t>(samples_per_frame) * 4);
		constexpr int kFrames = 300; // 約5秒（実機は約59.94fps）
		const PacingResult result = drive_and_capture(vm, samples_per_frame, kFrames, &ring);

		std::printf("frame_rate=%.4f samples_per_frame=%d extra_frames=%llu\n", frame_rate,
		            samples_per_frame, static_cast<unsigned long long>(result.total_extra_frames));

		// 起動直後の端数分だけ余剰が出ることはあるため、
		// 「1フレームあたり平均1未満」を合格条件にする。積み上がるなら
		// vm->run()とcreate_sound()が二重にVMを進めている。
		const double extra_per_frame = static_cast<double>(result.total_extra_frames) / kFrames;
		all_ok &= check(extra_per_frame < 1.0,
		                 "正しい設定では create_sound() が余剰フレームを積み上げない");

		delete emu;
	}

	// --- 2. 壊れた設定: sound_samples をわざと大きくする（検出器の自己検証） ---
	{
		EMU* emu = new EMU();
		VM_TEMPLATE* vm = emu->get_vm();
		const double frame_rate = vm->get_frame_rate();
		// upstreamの既定値（sound_latency_table[1]=100ms、emu.cpp）相当。
		// 1フレームの何倍もの音声を毎回要求するため、create_sound()が
		// 内部で余分にdrive()を呼ばざるを得ない。
		const int oversized_samples = kSoundRate / 10;
		vm->initialize_sound(kSoundRate, oversized_samples);

		bubi_spike::PcmRing ring(static_cast<std::size_t>(oversized_samples) * 4);
		constexpr int kFrames = 60;
		const PacingResult result = drive_and_capture(vm, oversized_samples, kFrames, &ring);

		const double extra_per_frame = static_cast<double>(result.total_extra_frames) / kFrames;
		std::printf("oversized samples_per_chunk=%d extra_frames=%llu\n", oversized_samples,
		            static_cast<unsigned long long>(result.total_extra_frames));
		all_ok &= check(extra_per_frame >= 1.0,
		                 "誤った設定では検出器が余剰フレームの積み上がりを検知する");

		(void)frame_rate;
		delete emu;
	}

	// --- 3. PCMリング: オーバーラン（書き手が速い） ---
	{
		bubi_spike::PcmRing ring(100);
		std::vector<int16_t> chunk(200 * 2, 1);
		const std::size_t overrun = ring.push(chunk.data(), 200);
		all_ok &= check(overrun == 100, "書き手が容量を超えた分は最古破棄で数える");
		all_ok &= check(ring.occupied_frames() == 100, "容量を超えて溜め込まない");
	}

	// --- 4. PCMリング: アンダーラン（読み手が速い） ---
	{
		bubi_spike::PcmRing ring(100);
		std::vector<int16_t> in(50 * 2, 2);
		ring.push(in.data(), 50);
		std::vector<int16_t> out(80 * 2, -1);
		const std::size_t underrun = ring.pop(out.data(), 80);
		all_ok &= check(underrun == 30, "足りない分をアンダーランとして数える");
		bool silence_ok = true;
		for (std::size_t i = 50 * 2; i < 80 * 2; ++i) {
			if (out[i] != 0) {
				silence_ok = false;
				break;
			}
		}
		all_ok &= check(silence_ok, "アンダーラン分は無音で埋める（プチノイズを出さない）");
	}

	std::printf("\n%s\n", all_ok ? "すべて合格" : "失敗あり");
	return all_ok ? EXIT_SUCCESS : EXIT_FAILURE;
}
