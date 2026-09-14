/*
 * RGBフィルター（native/bridge/src/rgb_filter.h、VID-04）の検査。
 *
 * 期待値は移植元（Windows版）のスクリーンショットで実測した画素値である。
 * 黒地（アルファ0）に白（0xffffff、アルファ0）の横線を置き、x1・x2・x3で
 * 背景・白の隣・白の端・白の内側がそれぞれ同じ値になることを確かめる。
 * コアを動かさずに走る。
 */
#include "rgb_filter.h"

#include <cstdint>
#include <cstdio>

using bubi::FilterBitmap;
using bubi::RgbFilter;

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

constexpr int kWidth = 640;
constexpr int kHeight = 400;
constexpr int kWhiteBegin = 10; // 白は x=10〜19
constexpr int kWhiteEnd = 20;

uint32_t rgb(int r, int g, int b)
{
	return (static_cast<uint32_t>(r) << 16) | (static_cast<uint32_t>(g) << 8) | static_cast<uint32_t>(b);
}

// 0行目と1行目に白の横線を引いた 640x400 の画面。
FilterBitmap make_source(uint32_t alpha)
{
	FilterBitmap source;
	source.resize(kWidth, kHeight);
	for (int y = 0; y < kHeight; ++y) {
		uint32_t* row = source.get_buffer(y);
		for (int x = 0; x < kWidth; ++x) {
			const bool white = y < 2 && x >= kWhiteBegin && x < kWhiteEnd;
			row[x] = alpha | (white ? 0xffffffu : 0u);
		}
	}
	return source;
}

FilterBitmap filter(FilterBitmap& source, int pow_x, int pow_y)
{
	RgbFilter rgb_filter;
	FilterBitmap dest;
	dest.resize(source.width * pow_x, source.height * pow_y);
	rgb_filter.apply(&source, &dest);
	return dest;
}

uint32_t at(FilterBitmap& bitmap, int x, int y)
{
	return bitmap.get_buffer(y)[x] & 0xffffffu;
}

// 白の左隣（x=9）、左端（x=10）、内側（x=15）と背景（x=100）。
constexpr int kNeighbor = kWhiteBegin - 1;
constexpr int kEdge = kWhiteBegin;
constexpr int kInner = 15;
constexpr int kBackground = 100;

} // namespace

int main()
{
	group("x1（apply_rgb_filter_x1_y1）");
	{
		FilterBitmap source = make_source(0);
		FilterBitmap dest = filter(source, 1, 1);
		check(at(dest, kBackground, 0) == rgb(32, 32, 32), "黒は32へ持ち上がる");
		check(at(dest, kNeighbor, 0) == rgb(53, 53, 53), "白の隣は1/8混ざって53");
		check(at(dest, kEdge, 0) == rgb(233, 233, 233), "白の端は233");
		check(at(dest, kInner, 0) == rgb(254, 254, 254), "白の内側は254");
		check(at(dest, kInner, 1) == rgb(254, 254, 254), "行は暗くしない");
	}

	group("x2（apply_rgb_filter_x2_y2）");
	{
		FilterBitmap source = make_source(0);
		FilterBitmap dest = filter(source, 2, 2);
		check(at(dest, kBackground * 2, 0) == rgb(32, 32, 32) &&
		          at(dest, kBackground * 2 + 1, 0) == rgb(16, 16, 16),
		      "黒は32と16の交互の列");
		check(at(dest, kNeighbor * 2, 0) == rgb(53, 53, 53) &&
		          at(dest, kNeighbor * 2 + 1, 0) == rgb(23, 23, 23),
		      "白の隣は53と23");
		check(at(dest, kEdge * 2, 0) == rgb(233, 233, 233) &&
		          at(dest, kEdge * 2 + 1, 0) == rgb(91, 91, 91),
		      "白の端は233と91");
		check(at(dest, kInner * 2, 0) == rgb(254, 254, 254) &&
		          at(dest, kInner * 2 + 1, 0) == rgb(98, 98, 98),
		      "白の内側は254と98");
		check(at(dest, kNeighbor * 2, 1) == rgb(39, 39, 39) &&
		          at(dest, kEdge * 2, 1) == rgb(107, 107, 107) &&
		          at(dest, kInner * 2, 1) == rgb(114, 114, 114) &&
		          at(dest, kInner * 2 + 1, 1) == rgb(98, 98, 98),
		      "アルファ0の画素の2行目は39・107・114へ暗くなる");
		check(at(dest, kBackground * 2, 1) == rgb(32, 32, 32) &&
		          at(dest, kBackground * 2 + 1, 1) == rgb(16, 16, 16),
		      "黒の2行目も32と16");
	}

	group("x2でアルファが0でなければ2行目を暗くしない");
	{
		FilterBitmap source = make_source(0xff000000u);
		FilterBitmap dest = filter(source, 2, 2);
		check(at(dest, kInner * 2, 1) == rgb(254, 254, 254), "2行目も254");
	}

	group("x3（apply_rgb_filter_x3_y3）");
	{
		FilterBitmap source = make_source(0);
		FilterBitmap dest = filter(source, 3, 3);
		check(at(dest, kBackground * 3, 0) == rgb(32, 0, 0) &&
		          at(dest, kBackground * 3 + 1, 0) == rgb(0, 32, 0) &&
		          at(dest, kBackground * 3 + 2, 0) == rgb(0, 0, 32),
		      "黒はR・G・B単色の32の列");
		check(at(dest, kNeighbor * 3, 0) == rgb(53, 0, 0) &&
		          at(dest, kNeighbor * 3 + 1, 0) == rgb(0, 53, 0) &&
		          at(dest, kNeighbor * 3 + 2, 0) == rgb(0, 0, 53),
		      "白の隣は単色の53");
		check(at(dest, kEdge * 3, 0) == rgb(233, 0, 0), "白の端は単色の233");
		check(at(dest, kInner * 3, 0) == rgb(254, 0, 0) &&
		          at(dest, kInner * 3 + 1, 0) == rgb(0, 254, 0) &&
		          at(dest, kInner * 3 + 2, 0) == rgb(0, 0, 254),
		      "白の内側は単色の254");
		check(at(dest, kInner * 3, 1) == rgb(254, 0, 0), "2行目は1行目と同じ");
		check(at(dest, kNeighbor * 3, 2) == rgb(39, 0, 0) &&
		          at(dest, kEdge * 3, 2) == rgb(107, 0, 0) &&
		          at(dest, kInner * 3, 2) == rgb(114, 0, 0),
		      "アルファ0の画素の3行目は39・107・114へ暗くなる");
		check(at(dest, kBackground * 3, 2) == rgb(32, 0, 0), "黒の3行目は32のまま");
	}

	group("x4・x5でも面を埋め切る");
	{
		FilterBitmap source = make_source(0);
		FilterBitmap x4 = filter(source, 4, 4);
		check(at(x4, 2559, 1599) != 0, "x4の右下まで書かれる");
		FilterBitmap x5 = filter(source, 5, 5);
		check(at(x5, 3199, 1999) != 0, "x5の右下まで書かれる");
	}

	if (failures != 0) {
		std::printf("%d failure(s)\n", failures);
		return 1;
	}
	std::printf("all passed\n");
	return 0;
}
