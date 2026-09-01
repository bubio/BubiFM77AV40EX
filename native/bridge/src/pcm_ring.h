/*
 * コアが生成したPCMを消費側へ渡す有界SPSCリング（design.md 7、16.1）。
 *
 * Core threadだけがpush()を呼ぶ。pull側（bfm_read_audio、任意のスレッド）が
 * pop()を呼ぶ。frame_ring.hの映像面と同じく、この実体はbfm_sessionが
 * 所有し、EMU/OSDの寿命とは独立に生き続ける。EMUを破棄した後もpop()が
 * 安全に呼べる必要があるため、OSD側の音声リング（bridge/osd/sdl/osd_sound.cpp、
 * upstream本来の「OSDが自分のタイマーでcreate_sound()を呼ぶ」設計の名残で
 * 未使用）は参照しない。
 */
#pragma once

#include <cstddef>
#include <cstdint>
#include <mutex>
#include <vector>

namespace bubi {

// design.md 7「音声設計」で固定した出力フォーマット。
constexpr int kAudioSampleRate = 48000;   // emu.cpp sound_frequency_table[6]
constexpr int kAudioChannels = 2;
constexpr double kAudioLatencySeconds = 0.1; // emu.cpp sound_latency_table[1]

// EMU::EMU()がconfig.sound_frequency/sound_latencyから計算するのと
// 同じ式（emu.cpp）。bridgeがこの2つのconfigフィールドを明示的に
// 設定するため、bridge側でも同じ値を再現できる（native/bridge/src/
// bubi_fm77av.cppのcore_thread_main参照）。
constexpr int kAudioSamplesPerCall =
    static_cast<int>(kAudioSampleRate * kAudioLatencySeconds + 0.5);

// 500ms分。生産と消費の速度差を吸収するための上限で、無制限には増やさない。
constexpr std::size_t kAudioRingCapacityFrames =
    static_cast<std::size_t>(kAudioSampleRate) / 2;

// ステレオ16bit PCMの有界リング。オーバーラン（書き手が読み手より速い）時は
// 最古のフレームを破棄する（design.md 4.3のイベントキューと同じ方針）。
// アンダーラン（読み手が書き手より速い）時は無音で埋める（design.md 7）。
class PcmRing {
public:
	PcmRing() : buffer_(kAudioRingCapacityFrames * kAudioChannels, 0) {}

	// [frames]分を書き込む。空きがなければ最古から上書きする。
	// srcがnullptrなら無音を書き込む（vm->create_sound()がNULLを返した場合の保険）。
	void push(const int16_t* src, std::size_t frames)
	{
		std::lock_guard<std::mutex> lock(mutex_);
		for (std::size_t i = 0; i < frames; ++i) {
			if (count_ >= kAudioRingCapacityFrames) {
				head_ = (head_ + 1) % kAudioRingCapacityFrames;
				--count_;
				++total_overrun_;
			}
			const std::size_t write_pos = (head_ + count_) % kAudioRingCapacityFrames;
			buffer_[write_pos * 2 + 0] = src != nullptr ? src[i * 2 + 0] : 0;
			buffer_[write_pos * 2 + 1] = src != nullptr ? src[i * 2 + 1] : 0;
			++count_;
		}
	}

	// 最大[frames]分を取り出す。足りない分は無音で埋める。
	void pop(int16_t* dst, std::size_t frames)
	{
		std::lock_guard<std::mutex> lock(mutex_);
		const std::size_t available = frames < count_ ? frames : count_;
		for (std::size_t i = 0; i < available; ++i) {
			const std::size_t read_pos = (head_ + i) % kAudioRingCapacityFrames;
			dst[i * 2 + 0] = buffer_[read_pos * 2 + 0];
			dst[i * 2 + 1] = buffer_[read_pos * 2 + 1];
		}
		for (std::size_t i = available; i < frames; ++i) {
			dst[i * 2 + 0] = 0;
			dst[i * 2 + 1] = 0;
		}
		head_ = (head_ + available) % kAudioRingCapacityFrames;
		count_ -= available;
		total_underrun_ += (frames - available);
	}

	std::size_t occupied_frames() const
	{
		std::lock_guard<std::mutex> lock(mutex_);
		return count_;
	}

	uint64_t total_overrun_frames() const
	{
		std::lock_guard<std::mutex> lock(mutex_);
		return total_overrun_;
	}

	uint64_t total_underrun_frames() const
	{
		std::lock_guard<std::mutex> lock(mutex_);
		return total_underrun_;
	}

private:
	mutable std::mutex mutex_;
	std::vector<int16_t> buffer_;
	std::size_t head_ = 0;
	std::size_t count_ = 0;
	uint64_t total_overrun_ = 0;
	uint64_t total_underrun_ = 0;
};

} // namespace bubi
