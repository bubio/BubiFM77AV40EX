/*
 * RGBフィルター（VID-04）。rgb_filter.h の説明を参照。
 *
 * apply_rgb_filter_to_screen_buffer 以下の関数本体は
 * native/core/upstream/src/win32/osd_screen.cpp（609〜1003行、
 * stretch_screen_buffer は1063〜1102行）の写しであり、計算を変えない。
 * 変えたのは次の点だけである。
 *   - RgbFilter:: を RgbFilter::、bitmap_t を FilterBitmap へ置き換えた。
 *   - initialize_screen_buffer() から GDI の COLORONCOLOR 引数を除いた。
 *   - ファイルstaticだった作業配列 r0〜b1 をメンバーへ移した。
 *   - stretch_screen_buffer の非整数倍で呼ぶ StretchBlt（COLORONCOLOR）を
 *     最近傍の縮尺へ置き換えた。
 */
#include "rgb_filter.h"

#include "common.h"

namespace bubi {

#define _3_8(v) (((((v) * 3) >> 3) * 180) >> 8)
#define _5_8(v) (((((v) * 3) >> 3) * 180) >> 8)
#define _8_8(v) (((v) * 180) >> 8)

void FilterBitmap::resize(int new_width, int new_height)
{
	width = new_width;
	height = new_height;
	pixels.assign(static_cast<size_t>(new_width) * new_height, 0);
}

void RgbFilter::apply(FilterBitmap *source, FilterBitmap *dest)
{
	// upstream は毎フレーム RgbFilter::draw_screen() の冒頭で false に戻す。
	screen_skip_line = false;
	// 作業配列は添字 width + 1 まで使う。FM77AV40EX の画面幅（640）では
	// 起きないが、超えると配列外へ書くため何もしない。
	if(source->width + 2 > kLineCapacity) {
		return;
	}
	apply_rgb_filter_to_screen_buffer(source, dest);
}

void RgbFilter::initialize_screen_buffer(FilterBitmap *buffer, int width, int height)
{
	buffer->resize(width, height);
}

void RgbFilter::apply_rgb_filter_to_screen_buffer(FilterBitmap *source, FilterBitmap *dest)
{
	if(source->width * 6 == dest->width && source->height * 6 == dest->height) {
		// FM-77AV: 320x200 -> 640x400 -> 1920x1200
		if(tmp_filtered_screen_buffer.width != source->width * 2 || tmp_filtered_screen_buffer.height != source->height * 2) {
			initialize_screen_buffer(&tmp_filtered_screen_buffer, source->width * 2, source->height * 2);
		}
		stretch_screen_buffer(source, &tmp_filtered_screen_buffer);
		screen_skip_line = true;
		apply_rgb_filter_x3_y3(&tmp_filtered_screen_buffer, dest);
	} else if(source->width * 3 == dest->width && source->height * 6 == dest->height) {
		// FM-77AV: 640x200 -> 640x400 -> 1920x1200
		if(tmp_filtered_screen_buffer.width != source->width || tmp_filtered_screen_buffer.height != source->height * 2) {
			initialize_screen_buffer(&tmp_filtered_screen_buffer, source->width, source->height * 2);
		}
		stretch_screen_buffer(source, &tmp_filtered_screen_buffer);
		screen_skip_line = true;
		apply_rgb_filter_x3_y3(&tmp_filtered_screen_buffer, dest);
	} else if(source->width * 4 == dest->width && source->height * 4 == dest->height) {
		// FM-77AV: 320x200 -> 640x400 -> 1280x800
		if(tmp_filtered_screen_buffer.width != source->width * 2 || tmp_filtered_screen_buffer.height != source->height * 2) {
			initialize_screen_buffer(&tmp_filtered_screen_buffer, source->width * 2, source->height * 2);
		}
		stretch_screen_buffer(source, &tmp_filtered_screen_buffer);
		screen_skip_line = true;
		apply_rgb_filter_x2_y2(&tmp_filtered_screen_buffer, dest);
	} else if(source->width * 2 == dest->width && source->height * 4 == dest->height) {
		// FM-77AV: 640x200 -> 640x400 -> 1280x800
		if(tmp_filtered_screen_buffer.width != source->width || tmp_filtered_screen_buffer.height != source->height * 2) {
			initialize_screen_buffer(&tmp_filtered_screen_buffer, source->width, source->height * 2);
		}
		stretch_screen_buffer(source, &tmp_filtered_screen_buffer);
		screen_skip_line = true;
		apply_rgb_filter_x2_y2(&tmp_filtered_screen_buffer, dest);
	} else if(source->width * 3 == dest->width && source->height * 3 == dest->height) {
		apply_rgb_filter_x3_y3(source, dest);
	} else if(source->width * 3 == dest->width && source->height * 2 == dest->height) {
		apply_rgb_filter_x3_y2(source, dest);
	} else if(source->width * 2 == dest->width && source->height * 3 == dest->height) {
		apply_rgb_filter_x2_y3(source, dest);
	} else if(source->width * 2 == dest->width && source->height * 2 == dest->height) {
		apply_rgb_filter_x2_y2(source, dest);
	} else if(source->width != dest->width || source->height != dest->height) {
		if(tmp_filtered_screen_buffer.width != source->width || tmp_filtered_screen_buffer.height != source->height) {
			initialize_screen_buffer(&tmp_filtered_screen_buffer, source->width, source->height);
		}
		apply_rgb_filter_x1_y1(source, &tmp_filtered_screen_buffer);
		stretch_screen_buffer(&tmp_filtered_screen_buffer, dest);
	} else {
		apply_rgb_filter_x1_y1(source, dest);
	}
}

void RgbFilter::apply_rgb_filter_x3_y3(FilterBitmap *source, FilterBitmap *dest)
{
	if(!screen_skip_line) {
		for(int y = 0, yy = 0; y < source->height; y++, yy += 3) {
			scrntype_t* src = source->get_buffer(y);
			scrntype_t* out1 = dest->get_buffer(yy + 0);
			scrntype_t* out2 = dest->get_buffer(yy + 1);
			scrntype_t* out3 = dest->get_buffer(yy + 2);
			
			for(int x = 1; x <= source->width; x++) {
				scrntype_t c = src[x - 1];
				t0[x] = A_OF_COLOR(c);
				r0[x] = R_OF_COLOR(c);
				g0[x] = G_OF_COLOR(c);
				b0[x] = B_OF_COLOR(c);
				r1[x] = r0[x] >> 3;
				g1[x] = g0[x] >> 3;
				b1[x] = b0[x] >> 3;
			}
			for(int x = 1, xx = 0; x <= source->width; x++, xx += 3) {
				uint32_t r = r1[x - 1] + r0[x] + r1[x + 1];
				uint32_t g = g1[x - 1] + g0[x] + g1[x + 1];
				uint32_t b = b1[x - 1] + b0[x] + b1[x + 1];
				out1[xx    ] = out2[xx    ] = (32 + _8_8(r)) << 16;
				out1[xx + 1] = out2[xx + 1] = (32 + _8_8(g)) << 8;
				out1[xx + 2] = out2[xx + 2] = (32 + _8_8(b));
				if(t0[x]) {
					out3[xx    ] = (32 + _8_8(r)) << 16;
					out3[xx + 1] = (32 + _8_8(g)) << 8;
					out3[xx + 2] = (32 + _8_8(b));
				} else {
					out3[xx    ] = (32 + _5_8(r)) << 16;
					out3[xx + 1] = (32 + _5_8(g)) << 8;
					out3[xx + 2] = (32 + _5_8(b));
				}
			}
		}
	} else {
		for(int y = 0, yy = 0; y < source->height; y += 2, yy += 6) {
			scrntype_t* src = source->get_buffer(y);
			scrntype_t* out1 = dest->get_buffer(yy + 0);
			scrntype_t* out2 = dest->get_buffer(yy + 1);
			scrntype_t* out3 = dest->get_buffer(yy + 2);
			scrntype_t* out4 = dest->get_buffer(yy + 3);
			scrntype_t* out5 = dest->get_buffer(yy + 4);
			scrntype_t* out6 = dest->get_buffer(yy + 5);
			
			for(int x = 1; x <= source->width; x++) {
				scrntype_t c = src[x - 1];
				t0[x] = A_OF_COLOR(c);
				r0[x] = R_OF_COLOR(c);
				g0[x] = G_OF_COLOR(c);
				b0[x] = B_OF_COLOR(c);
				r1[x] = r0[x] >> 3;
				g1[x] = g0[x] >> 3;
				b1[x] = b0[x] >> 3;
			}
			for(int x = 1, xx = 0; x <= source->width; x++, xx += 3) {
				uint32_t r = r1[x - 1] + r0[x] + r1[x + 1];
				uint32_t g = g1[x - 1] + g0[x] + g1[x + 1];
				uint32_t b = b1[x - 1] + b0[x] + b1[x + 1];
				out1[xx    ] = out2[xx    ] = out3[xx    ] = out4[xx    ] = (32 + _8_8(r)) << 16;
				out1[xx + 1] = out2[xx + 1] = out3[xx + 1] = out4[xx + 1] = (32 + _8_8(g)) << 8;
				out1[xx + 2] = out2[xx + 2] = out3[xx + 2] = out4[xx + 2] = (32 + _8_8(b));
				if(t0[x]) {
					out5[xx    ] = out6[xx    ] = (32 + _8_8(r)) << 16;
					out5[xx + 1] = out6[xx + 1] = (32 + _8_8(g)) << 8;
					out5[xx + 2] = out6[xx + 2] = (32 + _8_8(b));
				} else {
					out5[xx    ] = out6[xx    ] = (32 + _5_8(r)) << 16;
					out5[xx + 1] = out6[xx + 1] = (32 + _5_8(g)) << 8;
					out5[xx + 2] = out6[xx + 2] = (32 + _5_8(b));
				}
			}
		}
	}
}

void RgbFilter::apply_rgb_filter_x3_y2(FilterBitmap *source, FilterBitmap *dest)
{
	if(!screen_skip_line) {
		for(int y = 0, yy = 0; y < source->height; y++, yy += 2) {
			scrntype_t* src = source->get_buffer(y);
			scrntype_t* out1 = dest->get_buffer(yy + 0);
			scrntype_t* out2 = dest->get_buffer(yy + 1);
			
			for(int x = 1; x <= source->width; x++) {
				scrntype_t c = src[x - 1];
				t0[x] = A_OF_COLOR(c);
				r0[x] = R_OF_COLOR(c);
				g0[x] = G_OF_COLOR(c);
				b0[x] = B_OF_COLOR(c);
				r1[x] = r0[x] >> 3;
				g1[x] = g0[x] >> 3;
				b1[x] = b0[x] >> 3;
			}
			for(int x = 1, xx = 0; x <= source->width; x++, xx += 3) {
				uint32_t r = r1[x - 1] + r0[x] + r1[x + 1];
				uint32_t g = g1[x - 1] + g0[x] + g1[x + 1];
				uint32_t b = b1[x - 1] + b0[x] + b1[x + 1];
				out1[xx    ] = (32 + _8_8(r)) << 16;
				out1[xx + 1] = (32 + _8_8(g)) << 8;
				out1[xx + 2] = (32 + _8_8(b));
				if(t0[x]) {
					out2[xx    ] = (32 + _8_8(r)) << 16;
					out2[xx + 1] = (32 + _8_8(g)) << 8;
					out2[xx + 2] = (32 + _8_8(b));
				} else {
					out2[xx    ] = (32 + _5_8(r)) << 16;
					out2[xx + 1] = (32 + _5_8(g)) << 8;
					out2[xx + 2] = (32 + _5_8(b));
				}
			}
		}
	} else {
		for(int y = 0, yy = 0; y < source->height; y += 2, yy += 4) {
			scrntype_t* src = source->get_buffer(y);
			scrntype_t* out1 = dest->get_buffer(yy + 0);
			scrntype_t* out2 = dest->get_buffer(yy + 1);
			scrntype_t* out3 = dest->get_buffer(yy + 2);
			scrntype_t* out4 = dest->get_buffer(yy + 3);
			
			for(int x = 1; x <= source->width; x++) {
				scrntype_t c = src[x - 1];
				t0[x] = A_OF_COLOR(c);
				r0[x] = R_OF_COLOR(c);
				g0[x] = G_OF_COLOR(c);
				b0[x] = B_OF_COLOR(c);
				r1[x] = r0[x] >> 3;
				g1[x] = g0[x] >> 3;
				b1[x] = b0[x] >> 3;
			}
			for(int x = 1, xx = 0; x <= source->width; x++, xx += 3) {
				uint32_t r = r1[x - 1] + r0[x] + r1[x + 1];
				uint32_t g = g1[x - 1] + g0[x] + g1[x + 1];
				uint32_t b = b1[x - 1] + b0[x] + b1[x + 1];
				out1[xx    ] = out2[xx    ] = out3[xx    ] = (32 + _8_8(r)) << 16;
				out1[xx + 1] = out2[xx + 1] = out3[xx + 1] = (32 + _8_8(g)) << 8;
				out1[xx + 2] = out2[xx + 2] = out3[xx + 2] = (32 + _8_8(b));
				if(t0[x]) {
					out4[xx    ] = (32 + _8_8(r)) << 16;
					out4[xx + 1] = (32 + _8_8(g)) << 8;
					out4[xx + 2] = (32 + _8_8(b));
				} else {
					out4[xx    ] = (32 + _5_8(r)) << 16;
					out4[xx + 1] = (32 + _5_8(g)) << 8;
					out4[xx + 2] = (32 + _5_8(b));
				}
			}
		}
	}
}

void RgbFilter::apply_rgb_filter_x2_y3(FilterBitmap *source, FilterBitmap *dest)
{
	if(!screen_skip_line) {
		for(int y = 0, yy = 0; y < source->height; y++, yy += 3) {
			scrntype_t* src = source->get_buffer(y);
			scrntype_t* out1 = dest->get_buffer(yy + 0);
			scrntype_t* out2 = dest->get_buffer(yy + 1);
			scrntype_t* out3 = dest->get_buffer(yy + 2);
			
			for(int x = 1; x <= source->width; x++) {
				scrntype_t c = src[x - 1];
				t0[x] = A_OF_COLOR(c);
				r0[x] = R_OF_COLOR(c);
				g0[x] = G_OF_COLOR(c);
				b0[x] = B_OF_COLOR(c);
				r1[x] = r0[x] >> 3;
				g1[x] = g0[x] >> 3;
				b1[x] = b0[x] >> 3;
			}
			for(int x = 1, xx = 0; x <= source->width; x++, xx += 2) {
				uint32_t r = r1[x - 1] + r0[x] + r1[x + 1];
				uint32_t g = g1[x - 1] + g0[x] + g1[x + 1];
				uint32_t b = b1[x - 1] + b0[x] + b1[x + 1];
				out1[xx    ] = out2[xx    ] = RGB_COLOR(32 + _8_8(r), 32 + _8_8(g), 32 + _8_8(b));
				out1[xx + 1] = out2[xx + 1] = RGB_COLOR(16 + _5_8(r), 16 + _5_8(g), 16 + _5_8(b));
				if(t0[x]) {
					out3[xx    ] = RGB_COLOR(32 + _8_8(r), 32 + _8_8(g), 32 + _8_8(b));
					out3[xx + 1] = RGB_COLOR(16 + _5_8(r), 16 + _5_8(g), 16 + _5_8(b));
				} else {
					out3[xx    ] = RGB_COLOR(32 + _3_8(r), 32 + _3_8(g), 32 + _3_8(b));
					out3[xx + 1] = RGB_COLOR(16 + _3_8(r), 16 + _3_8(g), 16 + _3_8(b));
				}
			}
		}
	} else {
		for(int y = 0, yy = 0; y < source->height; y += 2, yy += 6) {
			scrntype_t* src = source->get_buffer(y);
			scrntype_t* out1 = dest->get_buffer(yy + 0);
			scrntype_t* out2 = dest->get_buffer(yy + 1);
			scrntype_t* out3 = dest->get_buffer(yy + 2);
			scrntype_t* out4 = dest->get_buffer(yy + 3);
			scrntype_t* out5 = dest->get_buffer(yy + 4);
			scrntype_t* out6 = dest->get_buffer(yy + 5);
			
			for(int x = 1; x <= source->width; x++) {
				scrntype_t c = src[x - 1];
				t0[x] = A_OF_COLOR(c);
				r0[x] = R_OF_COLOR(c);
				g0[x] = G_OF_COLOR(c);
				b0[x] = B_OF_COLOR(c);
				r1[x] = r0[x] >> 3;
				g1[x] = g0[x] >> 3;
				b1[x] = b0[x] >> 3;
			}
			for(int x = 1, xx = 0; x <= source->width; x++, xx += 2) {
				uint32_t r = r1[x - 1] + r0[x] + r1[x + 1];
				uint32_t g = g1[x - 1] + g0[x] + g1[x + 1];
				uint32_t b = b1[x - 1] + b0[x] + b1[x + 1];
				out1[xx    ] = out2[xx    ] = out3[xx    ] = out4[xx    ] = RGB_COLOR(32 + _8_8(r), 32 + _8_8(g), 32 + _8_8(b));
				out1[xx + 1] = out2[xx + 1] = out3[xx + 1] = out4[xx + 1] = RGB_COLOR(16 + _5_8(r), 16 + _5_8(g), 16 + _5_8(b));
				if(t0[x]) {
					out5[xx    ] = out6[xx    ] = RGB_COLOR(32 + _8_8(r), 32 + _8_8(g), 32 + _8_8(b));
					out5[xx + 1] = out6[xx + 1] = RGB_COLOR(16 + _5_8(r), 16 + _5_8(g), 16 + _5_8(b));
				} else {
					out5[xx    ] = out6[xx    ] = RGB_COLOR(32 + _3_8(r), 32 + _3_8(g), 32 + _3_8(b));
					out5[xx + 1] = out6[xx + 1] = RGB_COLOR(16 + _3_8(r), 16 + _3_8(g), 16 + _3_8(b));
				}
			}
		}
	}
}

void RgbFilter::apply_rgb_filter_x2_y2(FilterBitmap *source, FilterBitmap *dest)
{
	if(!screen_skip_line) {
		for(int y = 0, yy = 0; y < source->height; y++, yy += 2) {
			scrntype_t* src = source->get_buffer(y);
			scrntype_t* out1 = dest->get_buffer(yy + 0);
			scrntype_t* out2 = dest->get_buffer(yy + 1);
			
			for(int x = 1; x <= source->width; x++) {
				scrntype_t c = src[x - 1];
				t0[x] = A_OF_COLOR(c);
				r0[x] = R_OF_COLOR(c);
				g0[x] = G_OF_COLOR(c);
				b0[x] = B_OF_COLOR(c);
				r1[x] = r0[x] >> 3;
				g1[x] = g0[x] >> 3;
				b1[x] = b0[x] >> 3;
			}
			for(int x = 1, xx = 0; x <= source->width; x++, xx += 2) {
				uint32_t r = r1[x - 1] + r0[x] + r1[x + 1];
				uint32_t g = g1[x - 1] + g0[x] + g1[x + 1];
				uint32_t b = b1[x - 1] + b0[x] + b1[x + 1];
				out1[xx    ] = RGB_COLOR(32 + _8_8(r), 32 + _8_8(g), 32 + _8_8(b));
				out1[xx + 1] = RGB_COLOR(16 + _5_8(r), 16 + _5_8(g), 16 + _5_8(b));
				if(t0[x]) {
					out2[xx    ] = RGB_COLOR(32 + _8_8(r), 32 + _8_8(g), 32 + _8_8(b));
					out2[xx + 1] = RGB_COLOR(16 + _5_8(r), 16 + _5_8(g), 16 + _5_8(b));
				} else {
					out2[xx    ] = RGB_COLOR(32 + _3_8(r), 32 + _3_8(g), 32 + _3_8(b));
					out2[xx + 1] = RGB_COLOR(16 + _3_8(r), 16 + _3_8(g), 16 + _3_8(b));
				}
			}
		}
	} else {
		for(int y = 0, yy = 0; y < source->height; y += 2, yy += 4) {
			scrntype_t* src = source->get_buffer(y);
			scrntype_t* out1 = dest->get_buffer(yy + 0);
			scrntype_t* out2 = dest->get_buffer(yy + 1);
			scrntype_t* out3 = dest->get_buffer(yy + 2);
			scrntype_t* out4 = dest->get_buffer(yy + 3);
			
			for(int x = 1; x <= source->width; x++) {
				scrntype_t c = src[x - 1];
				t0[x] = A_OF_COLOR(c);
				r0[x] = R_OF_COLOR(c);
				g0[x] = G_OF_COLOR(c);
				b0[x] = B_OF_COLOR(c);
				r1[x] = r0[x] >> 3;
				g1[x] = g0[x] >> 3;
				b1[x] = b0[x] >> 3;
			}
			for(int x = 1, xx = 0; x <= source->width; x++, xx += 2) {
				uint32_t r = r1[x - 1] + r0[x] + r1[x + 1];
				uint32_t g = g1[x - 1] + g0[x] + g1[x + 1];
				uint32_t b = b1[x - 1] + b0[x] + b1[x + 1];
				out1[xx    ] = out2[xx    ] = out3[xx    ] = RGB_COLOR(32 + _8_8(r), 32 + _8_8(g), 32 + _8_8(b));
				out1[xx + 1] = out2[xx + 1] = out3[xx + 1] = RGB_COLOR(16 + _5_8(r), 16 + _5_8(g), 16 + _5_8(b));
				if(t0[x]) {
					out4[xx    ] = RGB_COLOR(32 + _8_8(r), 32 + _8_8(g), 32 + _8_8(b));
					out4[xx + 1] = RGB_COLOR(16 + _5_8(r), 16 + _5_8(g), 16 + _5_8(b));
				} else {
					out4[xx    ] = RGB_COLOR(32 + _3_8(r), 32 + _3_8(g), 32 + _3_8(b));
					out4[xx + 1] = RGB_COLOR(16 + _3_8(r), 16 + _3_8(g), 16 + _3_8(b));
				}
			}
		}
	}
}

void RgbFilter::apply_rgb_filter_x1_y1(FilterBitmap *source, FilterBitmap *dest)
{
	if(!screen_skip_line) {
		for(int y = 0; y < source->height; y++) {
			scrntype_t* src = source->get_buffer(y);
			scrntype_t* out1 = dest->get_buffer(y + 0);
			
			for(int x = 1; x <= source->width; x++) {
				scrntype_t c = src[x - 1];
				r0[x] = R_OF_COLOR(c);
				g0[x] = G_OF_COLOR(c);
				b0[x] = B_OF_COLOR(c);
				r1[x] = r0[x] >> 3;
				g1[x] = g0[x] >> 3;
				b1[x] = b0[x] >> 3;
			}
			for(int x = 1; x <= source->width; x++) {
				uint32_t r = r1[x - 1] + r0[x] + r1[x + 1];
				uint32_t g = g1[x - 1] + g0[x] + g1[x + 1];
				uint32_t b = b1[x - 1] + b0[x] + b1[x + 1];
				out1[x - 1] = RGB_COLOR(32 + _8_8(r), 32 + _8_8(g), 32 + _8_8(b));
			}
		}
	} else {
		for(int y = 0; y < source->height; y += 2) {
			scrntype_t* src = source->get_buffer(y);
			scrntype_t* out1 = dest->get_buffer(y + 0);
			scrntype_t* out2 = dest->get_buffer(y + 1);
			
			for(int x = 1; x <= source->width; x++) {
				scrntype_t c = src[x - 1];
				t0[x] = A_OF_COLOR(c);
				r0[x] = R_OF_COLOR(c);
				g0[x] = G_OF_COLOR(c);
				b0[x] = B_OF_COLOR(c);
				r1[x] = r0[x] >> 3;
				g1[x] = g0[x] >> 3;
				b1[x] = b0[x] >> 3;
			}
			for(int x = 1; x <= source->width; x++) {
				uint32_t r = r1[x - 1] + r0[x] + r1[x + 1];
				uint32_t g = g1[x - 1] + g0[x] + g1[x + 1];
				uint32_t b = b1[x - 1] + b0[x] + b1[x + 1];
				out1[x - 1] = RGB_COLOR(32 + _8_8(r), 32 + _8_8(g), 32 + _8_8(b));
				if(t0[x]) {
					out2[x - 1] = RGB_COLOR(32 + _8_8(r), 32 + _8_8(g), 32 + _8_8(b));
				} else {
					out2[x - 1] = RGB_COLOR(32 + _3_8(r), 32 + _3_8(g), 32 + _3_8(b));
				}
			}
		}
	}
}

void RgbFilter::stretch_screen_buffer(FilterBitmap *source, FilterBitmap *dest)
{
	if((dest->width % source->width) == 0 && (dest->height % source->height) == 0) {
		// faster than StretchBlt()
		int pow_x = dest->width / source->width;
		int pow_y = dest->height / source->height;
		
		for(int y = 0, yy = 0; y < source->height; y++, yy += pow_y) {
			scrntype_t* source_buffer = source->get_buffer(y);
			scrntype_t* dest_buffer = dest->get_buffer(yy);
			
			if(pow_x != 1) {
				scrntype_t* tmp_buffer = dest_buffer;
				for(int x = 0; x < source->width; x++) {
					scrntype_t c = source_buffer[x];
					for(int px = 0; px < pow_x; px++) {
						tmp_buffer[px] = c;
					}
					tmp_buffer += pow_x;
				}
			} else {
				// about 10% faster than memcpy()
				for(int x = 0; x < source->width; x++) {
					dest_buffer[x] = source_buffer[x];
				}
			}
			if(pow_y != 1) {
				for(int py = 1; py < pow_y; py++) {
					// about 10% faster than memcpy()
					scrntype_t* tmp_buffer = dest->get_buffer(yy + py);
					for(int x = 0; x < dest->width; x++) {
						tmp_buffer[x] = dest_buffer[x];
					}
				}
			}
		}
	} else {
		// StretchBlt(COLORONCOLOR) 相当の最近傍。
		for(int yy = 0; yy < dest->height; yy++) {
			scrntype_t* source_buffer = source->get_buffer(yy * source->height / dest->height);
			scrntype_t* dest_buffer = dest->get_buffer(yy);
			for(int xx = 0; xx < dest->width; xx++) {
				dest_buffer[xx] = source_buffer[xx * source->width / dest->width];
			}
		}
	}
}

} // namespace bubi
