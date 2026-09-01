/*
 * 【破棄可能なspike】M0 5.3 Textureゲートの検証用。
 * WP3で native/bridge/ の製品コードへ作り直し、このディレクトリごと消す。
 *
 * コアが書いた画面を、描画側（Flutterのraster thread）へ渡す仕組み。
 *
 * upstreamのバッファを直接見せてはならない。osd_screen.cpp の
 * allocate_screen_buffer() は release_screen_buffer() で free() してから
 * 確保し直すため、解像度が変わった瞬間に get_screen_buffer() の戻り値が
 * 無効になる。raster threadがそれを掴んでいると解放済みメモリを読む。
 * よってフレームはこちら側で持ち、Core threadが複製する。
 */
#pragma once

#include <atomic>
#include <cstdint>
#include <mutex>
#include <vector>

namespace bubi_spike {

struct FrameView {
	const uint32_t* pixels = nullptr; // BGRA8888、上から下へ
	uint32_t width = 0;
	uint32_t height = 0;
	uint64_t generation = 0; // 0は「まだ1枚もない」
};

/*
 * 3枚の面を回す。書込み中の面は誰にも見せず、読み手が持っている面は
 * 書き潰さない。読み手が遅れたら古い面を捨て、書き手は待たない。
 *
 * ロックは面の付け替えのあいだだけ持つ。画素の複製はロックの外で行う。
 * raster threadのcopyPixelBufferは同期呼出しなので、Core threadの
 * 複製を待たせるわけにはいかない。
 */
class FrameRing {
public:
	static constexpr int kSlots = 3;

	/* Core threadから呼ぶ。複製はロックの外で行う。 */
	void publish(const uint32_t* source, uint32_t width, uint32_t height);

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

	int pick_writable_slot();

	mutable std::mutex mutex_;
	Slot slots_[kSlots];
	int published_ = -1;
	std::atomic<uint64_t> published_generation_{0};
	std::atomic<uint64_t> dropped_{0};
	uint64_t next_generation_ = 1;
};

} // namespace bubi_spike
