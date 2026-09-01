/*
 * コアが描いた画面を描画側へ渡す面リング（design.md 6、16.1）。
 *
 * コアのバッファを描画側へ見せてはならない。OSD::draw_screen() は
 * 解像度が変わると allocate_screen_buffer() を呼び、これは
 * release_screen_buffer() で free() してから確保し直す。
 * get_screen_buffer() が返したポインターは 640x400 から 320x200 へ
 * 切り替わった瞬間に無効になる。描画側がそれを保持していれば
 * 解放済みメモリを読む。加えて描画側はCore threadではないため、
 * bfm_session::note_vm_access() の約束にも反する。
 *
 * よってフレームはここで所有し、Core threadが複製する。
 */
#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <vector>

namespace bubi {

struct FrameView {
	const uint32_t* pixels = nullptr; // BGRA8888、上から下へ、アルファは0xff
	uint32_t width = 0;
	uint32_t height = 0;
	uint64_t generation = 0; // 0は「まだ1枚もない」
};

/*
 * 3枚の面を回す。書込み中の面は誰にも見せず、借りられている面は
 * 書き潰さない。読み手が遅れたら古い面を捨て、書き手は待たない
 * （design.md 6「UIが遅れた場合は古い映像を捨て、コアを待たせない」）。
 *
 * ロックは面の付け替えのあいだだけ持ち、画素の複製はロックの外で行う。
 * macOSの copyPixelBuffer は raster thread から同期で呼ばれるため、
 * そこでCore threadの複製を待たせるわけにはいかない。
 *
 * 2枚では公開中と借用中で塞がり、書込みが公開中の面へ回り込んで破断する。
 */
class FrameRing {
public:
	static constexpr int kSlots = 3;

	/*
	 * Core threadから呼ぶ。fill_row(dst, y) が1行を書く。
	 * 複製はロックの外で行うため、fill_row の中で待ってはならない。
	 */
	template <typename FillRow>
	void publish(uint32_t width, uint32_t height, FillRow fill_row);

	/* 描画側から呼ぶ。最新の完成面を借りる。1枚もなければfalse。 */
	bool acquire(FrameView* out);

	/* 借りた面を返す。acquireとつねに対で呼ぶ。 */
	void release(uint64_t generation);

	uint64_t published_generation() const { return published_generation_.load(); }
	uint64_t dropped() const { return dropped_.load(); }

private:
	struct Slot {
		std::vector<uint32_t> pixels;
		uint32_t width = 0;
		uint32_t height = 0;
		uint64_t generation = 0;
		int borrowers = 0;
	};

	/* 呼び手はmutex_を保持していること。 */
	int pick_writable_slot();

	/* 書込み用に1枚囲い込む。取れなければ-1。 */
	int begin_write();

	/* 囲い込んだ面を公開する。 */
	void end_write(int index, uint32_t width, uint32_t height);

	mutable std::mutex mutex_;
	Slot slots_[kSlots];
	int published_ = -1;
	std::atomic<uint64_t> published_generation_{0};
	std::atomic<uint64_t> dropped_{0};
	uint64_t next_generation_ = 1;
};

template <typename FillRow>
void FrameRing::publish(uint32_t width, uint32_t height, FillRow fill_row)
{
	if (width == 0 || height == 0) {
		return;
	}
	const int index = begin_write();
	if (index < 0) {
		return;
	}

	Slot& slot = slots_[index];
	const size_t count = static_cast<size_t>(width) * height;
	if (slot.pixels.size() != count) {
		slot.pixels.resize(count);
	}
	for (uint32_t y = 0; y < height; ++y) {
		fill_row(slot.pixels.data() + static_cast<size_t>(y) * width, y);
	}

	end_write(index, width, height);
}

} // namespace bubi
