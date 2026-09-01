/*
 * 破棄可能なspike専用のPCM SPSCリング（M0 5.3 音声ゲート）。
 *
 * 製品版はWP4で`native/bridge/src/`へ作り直す。ここでの目的は方針の検証、
 * すなわちアンダーラン（読み手が書き手より速い）とオーバーラン
 * （書き手が読み手より速い）をそれぞれ再現し、無音埋めと最古破棄で
 * 安全に吸収できることを確かめることに限る。
 */
#pragma once

#include <cstdint>
#include <cstddef>
#include <vector>

namespace bubi_spike {

// ステレオ16bit PCMの有界リング。オーバーラン時は最古のフレームを破棄する
// （design.md 4.3のイベントキューと同じ方針。コマンドキューの「満杯で拒否」
// とは異なり、音声は取りこぼしよりも詰まりを避けることを優先する）。
class PcmRing {
public:
	explicit PcmRing(std::size_t capacity_frames)
		: buffer_(capacity_frames * 2, 0), capacity_(capacity_frames)
	{
	}

	// [frames]分を書き込む。空きがなければ最古から上書きする。
	// 戻り値は上書きで失った（オーバーランした）フレーム数。
	std::size_t push(const int16_t* src, std::size_t frames)
	{
		std::size_t overrun = 0;
		for (std::size_t i = 0; i < frames; ++i) {
			if (count_ >= capacity_) {
				head_ = (head_ + 1) % capacity_;
				--count_;
				++overrun;
			}
			const std::size_t write_pos = (head_ + count_) % capacity_;
			buffer_[write_pos * 2 + 0] = src[i * 2 + 0];
			buffer_[write_pos * 2 + 1] = src[i * 2 + 1];
			++count_;
		}
		total_overrun_ += overrun;
		return overrun;
	}

	// 最大[frames]分を取り出す。足りない分は無音で埋める。
	// 戻り値は無音で埋めた（アンダーランした）フレーム数。
	std::size_t pop(int16_t* dst, std::size_t frames)
	{
		const std::size_t available = frames < count_ ? frames : count_;
		for (std::size_t i = 0; i < available; ++i) {
			const std::size_t read_pos = (head_ + i) % capacity_;
			dst[i * 2 + 0] = buffer_[read_pos * 2 + 0];
			dst[i * 2 + 1] = buffer_[read_pos * 2 + 1];
		}
		const std::size_t underrun = frames - available;
		for (std::size_t i = available; i < frames; ++i) {
			dst[i * 2 + 0] = 0;
			dst[i * 2 + 1] = 0;
		}
		head_ = (head_ + available) % capacity_;
		count_ -= available;
		total_underrun_ += underrun;
		return underrun;
	}

	std::size_t occupied_frames() const { return count_; }
	std::size_t total_overrun_frames() const { return total_overrun_; }
	std::size_t total_underrun_frames() const { return total_underrun_; }

private:
	std::vector<int16_t> buffer_;
	std::size_t capacity_;
	std::size_t head_ = 0;
	std::size_t count_ = 0;
	std::size_t total_overrun_ = 0;
	std::size_t total_underrun_ = 0;
};

} // namespace bubi_spike
