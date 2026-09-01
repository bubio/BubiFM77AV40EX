/*
 * 【破棄可能なspike】M0 5.3 Textureゲートの検証用。
 *
 * 合格条件「破断や書込み競合なしに最新フレームを表示できる」を、
 * コアより厳しい条件で確かめる。
 *
 *   - 320x200 / 640x200 / 640x400 を毎フレーム切り替える
 *   - 書き手は59.94fpsより遥かに速く回す
 *   - 読み手はわざと遅らせ、取りこぼしを起こさせる
 *   - 画素は世代から一意に決まる値にし、1画素でも混ざれば破断として検出する
 */
#include "frame_ring.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <thread>
#include <vector>

using bubi_spike::FrameRing;
using bubi_spike::FrameView;

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

struct Size {
	uint32_t width;
	uint32_t height;
};

// design.md 6 が挙げるコアの論理解像度。
const Size kSizes[] = {{320, 200}, {640, 200}, {640, 400}};

/* 世代と位置から一意に決まる画素。1画素でも別世代なら混入を検出できる。 */
inline uint32_t pixel_of(uint64_t generation, uint32_t x, uint32_t y)
{
	const uint32_t g = static_cast<uint32_t>(generation);
	return (g * 2654435761u) ^ (x * 40503u) ^ (y * 12289u);
}

} // namespace

int main()
{
	FrameRing ring;
	std::atomic<bool> stop{false};
	std::atomic<uint64_t> produced{0};

	group("書き手を止めず、読み手が遅れても破断しない");

	std::thread producer([&] {
		std::vector<uint32_t> scratch;
		uint64_t frame = 0;
		while (!stop.load()) {
			const Size size = kSizes[frame % 3];
			const size_t count = static_cast<size_t>(size.width) * size.height;
			scratch.resize(count);
			// publish が採番する世代と一致させるため、こちらでも同じ順に数える。
			const uint64_t generation = frame + 1;
			for (uint32_t y = 0; y < size.height; ++y) {
				for (uint32_t x = 0; x < size.width; ++x) {
					scratch[static_cast<size_t>(y) * size.width + x] =
						pixel_of(generation, x, y);
				}
			}
			ring.publish(scratch.data(), size.width, size.height);
			produced.fetch_add(1);
			++frame;
		}
	});

	uint64_t consumed = 0;
	uint64_t last_generation = 0;
	bool torn = false;
	bool went_backwards = false;
	bool wrong_size = false;

	const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
	while (std::chrono::steady_clock::now() < deadline) {
		FrameView view;
		if (!ring.acquire(&view)) {
			continue;
		}
		if (view.generation < last_generation) {
			went_backwards = true;
		}
		last_generation = view.generation;

		bool size_known = false;
		for (const Size& size : kSizes) {
			if (view.width == size.width && view.height == size.height) {
				size_known = true;
			}
		}
		if (!size_known) {
			wrong_size = true;
		}

		// 全画素を確かめる。1画素でも別世代の値なら破断である。
		for (uint32_t y = 0; y < view.height && !torn; ++y) {
			for (uint32_t x = 0; x < view.width; ++x) {
				if (view.pixels[static_cast<size_t>(y) * view.width + x] !=
				    pixel_of(view.generation, x, y)) {
					torn = true;
					break;
				}
			}
		}

		// 読み手をわざと遅らせ、書き手に取りこぼしを起こさせる。
		std::this_thread::sleep_for(std::chrono::milliseconds(2));
		ring.release(view.generation);
		++consumed;
	}

	stop.store(true);
	producer.join();

	check(!torn, "取り出した面に別世代の画素が混ざらない");
	check(!went_backwards, "世代が戻らない");
	check(!wrong_size, "解像度が切り替わっても大きさが矛盾しない");
	check(produced.load() > consumed * 2,
	      "読み手が遅れても書き手は待たされない");
	check(ring.dropped() == 0, "3枚あれば書ける面が尽きない");
	check(consumed > 0, "読み手が面を取り出せている");
	std::printf("   生成 %llu 枚 / 取出し %llu 枚\n",
	            static_cast<unsigned long long>(produced.load()),
	            static_cast<unsigned long long>(consumed));

	group("借りているあいだは書き潰されない");
	{
		FrameRing held;
		std::vector<uint32_t> a(320 * 200, 0x11111111u);
		held.publish(a.data(), 320, 200);
		FrameView borrowed;
		check(held.acquire(&borrowed), "1枚目を借りられる");
		const uint32_t first = borrowed.pixels[0];
		// 借りたまま別の大きさで何枚も上書きする。
		std::vector<uint32_t> b(640 * 400, 0x22222222u);
		for (int i = 0; i < 10; ++i) {
			held.publish(b.data(), 640, 400);
		}
		check(borrowed.pixels[0] == first, "借りている面の中身が変わらない");
		check(borrowed.width == 320 && borrowed.height == 200,
		      "借りている面の大きさが変わらない");
		held.release(borrowed.generation);

		FrameView latest;
		check(held.acquire(&latest), "返した後は最新を借りられる");
		check(latest.width == 640 && latest.height == 400, "最新は新しい解像度");
		check(latest.generation == held.published_generation(), "最新の世代が一致する");
		held.release(latest.generation);
	}

	if (failures == 0) {
		std::printf("\nすべて合格\n");
		return 0;
	}
	std::printf("\n失敗: %d 件\n", failures);
	return 1;
}
