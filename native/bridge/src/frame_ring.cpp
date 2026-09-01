#include "frame_ring.h"

namespace bubi {

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

int FrameRing::begin_write()
{
	std::lock_guard<std::mutex> lock(mutex_);
	const int index = pick_writable_slot();
	if (index < 0) {
		dropped_.fetch_add(1);
		return -1;
	}
	// 借用数を1にして囲い込む。複製のあいだ読み手へ渡らない。
	slots_[index].borrowers = 1;
	slots_[index].generation = 0; // 未完成。誰にも見せない。
	return index;
}

void FrameRing::end_write(int index, uint32_t width, uint32_t height)
{
	std::lock_guard<std::mutex> lock(mutex_);
	Slot& slot = slots_[index];
	slot.width = width;
	slot.height = height;
	slot.generation = next_generation_++;
	slot.borrowers = 0;
	published_ = index;
	published_generation_.store(slot.generation);
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

} // namespace bubi
