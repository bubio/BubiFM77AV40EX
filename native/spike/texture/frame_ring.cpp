/* 【破棄可能なspike】M0 5.3 Textureゲートの検証用。 */
#include "frame_ring.h"

#include <cstring>

namespace bubi_spike {

/* 呼び手はmutex_を保持していること。 */
int FrameRing::pick_writable_slot()
{
	// 公開中でも借りられてもいない面を選ぶ。
	for (int i = 0; i < kSlots; ++i) {
		if (i != published_ && slots_[i].borrowers == 0) {
			return i;
		}
	}
	// 3枚あれば必ず1枚は空く。公開中1枚＋借用中1枚が上限のため。
	return -1;
}

void FrameRing::publish(const uint32_t* source, uint32_t width, uint32_t height)
{
	if (source == nullptr || width == 0 || height == 0) {
		return;
	}

	int index = -1;
	{
		std::lock_guard<std::mutex> lock(mutex_);
		index = pick_writable_slot();
		if (index < 0) {
			dropped_.fetch_add(1);
			return;
		}
		// 選んだ面を「書込み中」として囲い込む。借用数を1にしておくと
		// 複製のあいだに読み手へ渡らない。
		slots_[index].borrowers = 1;
		slots_[index].generation = 0; // 未完成。誰にも見せない。
	}

	Slot& slot = slots_[index];
	const size_t count = static_cast<size_t>(width) * height;
	if (slot.pixels.size() != count) {
		slot.pixels.resize(count);
	}
	std::memcpy(slot.pixels.data(), source, count * sizeof(uint32_t));
	slot.width = width;
	slot.height = height;

	{
		std::lock_guard<std::mutex> lock(mutex_);
		slot.generation = next_generation_++;
		slot.borrowers = 0;
		published_ = index;
		published_generation_.store(slot.generation);
	}
}

bool FrameRing::acquire(FrameView* out)
{
	if (out == nullptr) {
		return false;
	}
	std::lock_guard<std::mutex> lock(mutex_);
	if (published_ < 0) {
		return false;
	}
	Slot& slot = slots_[published_];
	if (slot.generation == 0) {
		return false;
	}
	++slot.borrowers;
	out->pixels = slot.pixels.data();
	out->width = slot.width;
	out->height = slot.height;
	out->generation = slot.generation;
	return true;
}

void FrameRing::release(uint64_t generation)
{
	std::lock_guard<std::mutex> lock(mutex_);
	for (Slot& slot : slots_) {
		if (slot.generation == generation && slot.borrowers > 0) {
			--slot.borrowers;
			return;
		}
	}
}

} // namespace bubi_spike
