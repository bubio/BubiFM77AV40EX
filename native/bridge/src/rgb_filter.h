/*
 * RGBフィルター（VID-04、Host > Screen > Filter > RGB）。
 *
 * 移植元のWin32版は OSD::draw_screen() の中で、コアが描いた画面
 * （vm_screen_buffer）を「表示倍率の整数切り上げ」倍の大きさへ広げながら
 * フィルターを掛ける（osd_screen.cpp の apply_rgb_filter_to_screen_buffer）。
 * 倍率ごとに別の関数を使い、黒を32へ持ち上げる、x3では1画素をR/G/B単色の
 * 3列に分ける、隣の画素を1/8混ぜる、アルファが0の画素の行を暗くする、
 * といった画素値そのものの計算をする。表示側の掛け算では再現できないため、
 * 同じ計算をここでCore threadが行い、結果の面をTextureへ渡す。
 *
 * 画素の並びはコアと同じ scrntype_t（0xAARRGGBB）。
 */
#pragma once

#include <cstddef>
#include <cstdint>
#include <vector>

namespace bubi {

struct FilterBitmap {
	std::vector<uint32_t> pixels;
	int width = 0;
	int height = 0;

	uint32_t* get_buffer(int y) { return pixels.data() + static_cast<size_t>(y) * width; }
	void resize(int new_width, int new_height);
};

class RgbFilter {
public:
	/*
	 * source（コアの画面）へフィルターを掛けて dest へ書く。dest の大きさは
	 * 呼び出し側が source の幅・高さ × 倍率（upstream の tmp_pow_x/y）で
	 * 確保しておくこと。出力のアルファは upstream と同じく0のままである。
	 */
	void apply(FilterBitmap *source, FilterBitmap *dest);

private:
	static constexpr int kLineCapacity = 2048;

	void initialize_screen_buffer(FilterBitmap *buffer, int width, int height);
	void apply_rgb_filter_to_screen_buffer(FilterBitmap *source, FilterBitmap *dest);
	void apply_rgb_filter_x3_y3(FilterBitmap *source, FilterBitmap *dest);
	void apply_rgb_filter_x3_y2(FilterBitmap *source, FilterBitmap *dest);
	void apply_rgb_filter_x2_y3(FilterBitmap *source, FilterBitmap *dest);
	void apply_rgb_filter_x2_y2(FilterBitmap *source, FilterBitmap *dest);
	void apply_rgb_filter_x1_y1(FilterBitmap *source, FilterBitmap *dest);
	void stretch_screen_buffer(FilterBitmap *source, FilterBitmap *dest);

	bool screen_skip_line = false;
	FilterBitmap tmp_filtered_screen_buffer;

	// upstream ではファイルstaticの作業配列。添字 width + 1 まで使う。
	uint8_t r0[kLineCapacity] = {}, g0[kLineCapacity] = {}, b0[kLineCapacity] = {}, t0[kLineCapacity] = {};
	uint8_t r1[kLineCapacity] = {}, g1[kLineCapacity] = {}, b1[kLineCapacity] = {};
};

} // namespace bubi
