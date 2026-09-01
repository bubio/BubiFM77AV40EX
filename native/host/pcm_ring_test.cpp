/*
 * 音声リング（native/bridge/src/pcm_ring.h）の検査。
 *
 * development_plan.md 6 WP4「アンダーラン、オーバーラン、停止...をテストする」
 * を、native/spike/sound/（WP4着手にあたり削除）が検証した方針の製品版として
 * 確かめる。コアを必要とせず、CIで走る。
 */
#include "pcm_ring.h"

#include <cstdio>
#include <vector>

using bubi::kAudioChannels;
using bubi::kAudioRingCapacityFrames;
using bubi::PcmRing;

namespace {

int failures = 0;

void check(bool condition, const char* what)
{
	std::printf("  [%s] %s\n", condition ? " ok " : "FAIL", what);
	if (!condition) {
		++failures;
	}
}

void group(const char* name)
{
	std::printf("== %s\n", name);
}

std::vector<int16_t> make_tone(std::size_t frames, int16_t value)
{
	std::vector<int16_t> v(frames * kAudioChannels);
	for (std::size_t i = 0; i < frames; ++i) {
		v[i * 2 + 0] = value;
		v[i * 2 + 1] = static_cast<int16_t>(-value);
	}
	return v;
}

} // namespace

int main()
{
	group("空のリングから読むとアンダーランで無音が埋まる");
	{
		PcmRing ring;
		std::vector<int16_t> out(200 * kAudioChannels, 0x1234);
		ring.pop(out.data(), 100);
		bool all_silent = true;
		for (std::size_t i = 0; i < 100 * kAudioChannels; ++i) {
			if (out[i] != 0) {
				all_silent = false;
			}
		}
		check(all_silent, "取り出したフレームがすべて無音");
		check(ring.total_underrun_frames() == 100, "アンダーランしたフレーム数が積算される");
		check(ring.total_overrun_frames() == 0, "オーバーランは起きていない");
	}

	group("書いた分だけ正しく取り出せる（アンダーランなし）");
	{
		PcmRing ring;
		const auto tone = make_tone(50, 1000);
		ring.push(tone.data(), 50);
		check(ring.occupied_frames() == 50, "書いた分だけ溜まっている");

		std::vector<int16_t> out(50 * kAudioChannels, 0);
		ring.pop(out.data(), 50);
		check(out == tone, "書いた値がそのまま読み出せる");
		check(ring.total_underrun_frames() == 0, "十分溜まっていればアンダーランしない");
		check(ring.occupied_frames() == 0, "取り出した分だけ空になる");
	}

	group("読み手より書き手が速いとオーバーランし、最古から捨てる");
	{
		PcmRing ring;
		// 容量を超える分を1フレームずつ書き、後半だけが残ることを確かめる。
		// 値はフレーム番号そのものにし、生き残る範囲を厳密に特定できるようにする。
		const std::size_t total = kAudioRingCapacityFrames + 1000;
		for (std::size_t i = 0; i < total; ++i) {
			const auto tone = make_tone(1, static_cast<int16_t>(i % 30000));
			ring.push(tone.data(), 1);
		}
		check(ring.occupied_frames() == kAudioRingCapacityFrames,
		      "容量を超えて溜まらない（有界）");
		check(ring.total_overrun_frames() == 1000, "捨てた分だけオーバーランが積算される");

		std::vector<int16_t> out(kAudioRingCapacityFrames * kAudioChannels, 0);
		ring.pop(out.data(), kAudioRingCapacityFrames);
		// 最古の1000フレームを捨てたので、生き残りは frame[1000] から始まる。
		const int16_t expected_first = static_cast<int16_t>(1000 % 30000);
		const int16_t expected_last = static_cast<int16_t>((total - 1) % 30000);
		check(out[0] == expected_first, "生き残った先頭は最古ではなく直近のデータ");
		check(out[(kAudioRingCapacityFrames - 1) * kAudioChannels] == expected_last,
		      "生き残った末尾は最後に書いた値");
	}

	group("nullptrで書くと無音を書き込む（vm->create_sound()のNULL保険）");
	{
		PcmRing ring;
		ring.push(nullptr, 10);
		std::vector<int16_t> out(10 * kAudioChannels, 0x1234);
		ring.pop(out.data(), 10);
		bool all_silent = true;
		for (std::size_t i = 0; i < 10 * kAudioChannels; ++i) {
			if (out[i] != 0) {
				all_silent = false;
			}
		}
		check(all_silent, "nullptr push は無音として扱われる");
		check(ring.total_underrun_frames() == 0, "書き込み済みなのでアンダーランではない");
	}

	group("停止後（新しいリング）は無音で安全に読める");
	{
		// bfm_session::audioはCore threadの停止・emu破棄と寿命が独立している
		// （pcm_ring.h）。新規リング＝停止直後の状態を模す。
		PcmRing ring;
		std::vector<int16_t> out(4800 * kAudioChannels, 0x1234);
		ring.pop(out.data(), 4800);
		bool all_silent = true;
		for (std::size_t i = 0; i < 4800 * kAudioChannels; ++i) {
			if (out[i] != 0) {
				all_silent = false;
			}
		}
		check(all_silent, "停止直後の読み出しはクラッシュせず無音を返す");
	}

	if (failures == 0) {
		std::printf("\nすべて合格\n");
		return 0;
	}
	std::printf("\n失敗: %d 件\n", failures);
	return 1;
}
