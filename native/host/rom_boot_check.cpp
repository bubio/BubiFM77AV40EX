/*
 * 実ROMでの起動確認（development_plan.md 6 WP2 最終項目）。
 *
 * CIでは実行しない。利用者が自分のROMを置いた機械でだけ意味を持つ。
 * ROMを引数で受け取り、内容も名前も出力しない。
 *
 * やること
 *   1. 実ROMでBASIC起動。数百フレーム進めてから画面を1枚取り出す。
 *   2. 同じ名前の0埋めダミーでもう一度起動し、画面を取り出す。
 *   3. 実ROMの画面が「真っ黒でない」かつ「ダミーと違う」ことを確かめる。
 *   4. DOSモードでも起動し、媒体がないときは実機と同じくBASICへ落ちる
 *      ことを確かめる。媒体からのDOS起動確認はWP5（FDD）で行う。
 *   5. VM操作の見張り（vm_access_violations）が0のままであることを確かめる。
 *
 * 画面はPPMで書き出す。出力先は引数で受け取り、リポジトリには置かない。
 */
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#include "bubi_fm77av.h"

extern "C" bfm_result bfm_test_capture_screen(bfm_session* session, uint32_t* out_pixels,
                                              uint32_t max_pixels, int32_t* out_width,
                                              int32_t* out_height);

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

struct Frame {
	int32_t width = 0;
	int32_t height = 0;
	std::vector<uint32_t> pixels;

	bool blank() const
	{
		if (pixels.empty()) {
			return true;
		}
		const uint32_t first = pixels.front() | 0xff000000u;
		for (const uint32_t pixel : pixels) {
			if ((pixel | 0xff000000u) != first) {
				return false;
			}
		}
		return true;
	}
};

bool operator==(const Frame& a, const Frame& b)
{
	return a.width == b.width && a.height == b.height && a.pixels == b.pixels;
}

/* コアの想定フレーム数まで進むのを待つ。固定sleepにしない。 */
bool wait_for_frames(bfm_session* session, uint64_t target, int timeout_seconds)
{
	const auto deadline =
		std::chrono::steady_clock::now() + std::chrono::seconds(timeout_seconds);
	for (;;) {
		bfm_stats stats{};
		if (bfm_get_stats(session, &stats) == BFM_OK && stats.frames_run >= target) {
			return true;
		}
		if (std::chrono::steady_clock::now() >= deadline) {
			return false;
		}
		std::this_thread::sleep_for(std::chrono::milliseconds(20));
	}
}

/*
 * 1回起動して画面を1枚取り出す。
 * home_dir はプロセス全体で1つに固定されるため、呼び出しごとに変えない。
 */
bool boot_and_capture(const std::string& home, const std::string& rom_dir,
                      bfm_boot_mode boot_mode, uint64_t frames, Frame* out,
                      uint64_t* out_violations)
{
	bfm_create_options options{};
	options.home_dir = home.c_str();
	options.rom_dir = rom_dir.c_str();
	options.boot_mode = boot_mode;

	bfm_session* session = nullptr;
	if (bfm_create(&options, &session) != BFM_OK) {
		return false;
	}
	bool ok = bfm_start(session) == BFM_OK && wait_for_frames(session, frames, 60);
	if (ok) {
		int32_t width = 0;
		int32_t height = 0;
		std::vector<uint32_t> pixels(640 * 400 * 2);
		const bfm_result code = bfm_test_capture_screen(
			session, pixels.data(), static_cast<uint32_t>(pixels.size()), &width, &height);
		ok = code == BFM_OK && width > 0 && height > 0;
		if (ok) {
			pixels.resize(static_cast<size_t>(width) * height);
			out->width = width;
			out->height = height;
			out->pixels.swap(pixels);
		}
	}
	bfm_stats stats{};
	if (bfm_get_stats(session, &stats) == BFM_OK) {
		*out_violations += stats.vm_access_violations;
	}
	bfm_stop(session);
	bfm_destroy(session);
	return ok;
}

bool write_ppm(const std::string& path, const Frame& frame)
{
	FILE* fp = std::fopen(path.c_str(), "wb");
	if (fp == nullptr) {
		return false;
	}
	std::fprintf(fp, "P6\n%d %d\n255\n", frame.width, frame.height);
	for (const uint32_t pixel : frame.pixels) {
		// コアのバッファはARGB8888。上位のアルファは捨てる。
		const unsigned char rgb[3] = {
			static_cast<unsigned char>((pixel >> 16) & 0xff),
			static_cast<unsigned char>((pixel >> 8) & 0xff),
			static_cast<unsigned char>(pixel & 0xff),
		};
		std::fwrite(rgb, 1, 3, fp);
	}
	const bool ok = std::ferror(fp) == 0;
	std::fclose(fp);
	return ok;
}

/* 実ROMと同じ名前で0埋めのダミーを作る。比較の対照に使う。 */
bool make_dummy_roms(const std::string& rom_dir, const std::string& dummy_dir)
{
	if (mkdir(dummy_dir.c_str(), 0700) != 0 && errno != EEXIST) {
		return false;
	}
	static const char* const names[] = {
		"INITIATE.ROM", "SUBSYS_A.ROM", "SUBSYS_B.ROM", "SUBSYS_C.ROM",
		"SUBSYSCG.ROM", "EXTSUB.ROM",   "FBASIC30.ROM",
	};
	static const size_t sizes[] = {
		8 * 1024, 8 * 1024, 8 * 1024, 10 * 1024, 8 * 1024, 48 * 1024, 31 * 1024,
	};
	for (size_t i = 0; i < sizeof(names) / sizeof(names[0]); ++i) {
		const std::string path = dummy_dir + "/" + names[i];
		FILE* fp = std::fopen(path.c_str(), "wb");
		if (fp == nullptr) {
			return false;
		}
		const std::vector<char> zeros(sizes[i], 0);
		std::fwrite(zeros.data(), 1, zeros.size(), fp);
		std::fclose(fp);
	}
	(void)rom_dir;
	return true;
}

} // namespace

int main(int argc, char** argv)
{
	if (argc < 4) {
		std::fprintf(stderr,
		             "usage: rom_boot_check <home_dir> <rom_dir> <output_dir> [frames]\n");
		return 2;
	}
	const std::string home = argv[1];
	const std::string rom_dir = argv[2];
	const std::string out_dir = argv[3];
	const uint64_t frames = (argc > 4) ? std::strtoull(argv[4], nullptr, 10) : 300;

	uint64_t violations = 0;

	group("実ROMでBASIC起動");
	Frame basic;
	const bool basic_ok =
		boot_and_capture(home, rom_dir, BFM_BOOT_BASIC, frames, &basic, &violations);
	check(basic_ok, "起動して画面を取り出せる");
	if (!basic_ok) {
		std::printf("\n失敗: %d 件\n", failures + 1);
		return 1;
	}
	check(basic.width > 0 && basic.height > 0, "画面の大きさが取れている");
	check(!basic.blank(), "画面が単色でない");
	const std::string basic_path = out_dir + "/boot_basic.ppm";
	check(write_ppm(basic_path, basic), "BASIC画面を書き出せる");
	std::printf("   画面: %dx%d -> %s\n", basic.width, basic.height, basic_path.c_str());

	group("0埋めダミーとの比較");
	const std::string dummy_dir = out_dir + "/dummy_roms";
	Frame dummy;
	if (!make_dummy_roms(rom_dir, dummy_dir)) {
		check(false, "ダミーROMを用意できる");
	} else {
		const bool dummy_ok =
			boot_and_capture(home, dummy_dir, BFM_BOOT_BASIC, frames, &dummy, &violations);
		check(dummy_ok, "ダミーでも起動自体はできる");
		check(!dummy_ok || !(basic == dummy), "実ROMの画面がダミーと異なる");
		if (dummy_ok) {
			write_ppm(out_dir + "/boot_dummy.ppm", dummy);
		}
	}

	group("DOSモード");
	Frame dos;
	const bool dos_ok =
		boot_and_capture(home, rom_dir, BFM_BOOT_DOS, frames, &dos, &violations);
	check(dos_ok, "DOSモードで起動できる");
	check(!dos_ok || !dos.blank(), "DOSモードの画面が単色でない");
	// 媒体がないとき、DOSのブートROMはF-BASICへ落ちる。実機と同じ挙動なので、
	// ここでBASICと同じ画面になるのは正常である。媒体からのDOS起動確認は
	// WP5（FDD）で行う。
	check(!dos_ok || basic == dos, "媒体がないDOSモードはBASICへ落ちる（実機と同じ）");
	if (dos_ok) {
		write_ppm(out_dir + "/boot_dos.ppm", dos);
	}

	group("VM操作の見張り");
	check(violations == 0, "Core thread以外からVMへ触っていない");

	if (failures == 0) {
		std::printf("\nすべて合格\n");
		return 0;
	}
	std::printf("\n失敗: %d 件\n", failures);
	return 1;
}
