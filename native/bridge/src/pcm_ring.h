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

// Host > Sound の「オーディオバッファ」設定（bfm_audio_latency、
// bubi_fm77av.h）が選べる4値。emu.cpp sound_latency_table[0..3]と同じ値
// （[4]=0.4秒は使わない）。既定は[0]の50ms。
constexpr double kAudioLatencyOptionsSeconds[4] = {0.05, 0.1, 0.2, 0.3};

// EMU::EMU()がconfig.sound_frequency/sound_latencyから計算するのと
// 同じ式（emu.cpp）。bridgeがこの2つのconfigフィールドを明示的に
// 設定するため、bridge側でも同じ値を再現できる（native/bridge/src/
// bubi_fm77av.cppのcore_thread_main参照）。
constexpr int kAudioSamplesForLatency(int latency_index)
{
	return static_cast<int>(
	    kAudioSampleRate * kAudioLatencyOptionsSeconds[latency_index] + 0.5);
}

// 1秒分。生産と消費の速度差を吸収するための上限で、無制限には増やさない。
// 最大のバッファ設定（300ms）でも十分な余裕を残すため、既定（100ms）の
// 500msから引き上げた。
constexpr std::size_t kAudioRingCapacityFrames =
    static_cast<std::size_t>(kAudioSampleRate);

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

	// 溜まっている分だけ、最大[frames]分を取り出して取り出した数を返す。
	// pop()と違い無音で埋めず、アンダーランにも数えない。生成が一定量の
	// まとまり（audio_latency分）で届くため、固定量を無音埋めで読む
	// pop()を短い周期で呼ぶと、まとまりの隙間ごとに無音が挟まり音が途切れる。
	std::size_t pop_available(int16_t* dst, std::size_t frames)
	{
		std::lock_guard<std::mutex> lock(mutex_);
		const std::size_t available = frames < count_ ? frames : count_;
		for (std::size_t i = 0; i < available; ++i) {
			const std::size_t read_pos = (head_ + i) % kAudioRingCapacityFrames;
			dst[i * 2 + 0] = buffer_[read_pos * 2 + 0];
			dst[i * 2 + 1] = buffer_[read_pos * 2 + 1];
		}
		head_ = (head_ + available) % kAudioRingCapacityFrames;
		count_ -= available;
		return available;
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
