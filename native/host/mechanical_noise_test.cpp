/*
 * FDD・CMT機構音の素材の合成（native/bridge/src/mechanical_noise.h、
 * AUD-04/AUD-07）の検査。
 *
 * upstream NOISE::load_wav_file() が読める形のWAVであること、早送り音が
 * 継ぎ目なくループすること、利用者のWAVを消さず上書きもしないことを
 * 確かめる。コアを動かさずに走る。
 */
#include "mechanical_noise.h"

#if !defined(_WIN32)
#include <sys/stat.h>
#include <unistd.h>
#endif

#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <iterator>
#include <string>
#include <vector>

using bubi::MechanicalNoiseKind;

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

uint32_t read_u32(const std::vector<uint8_t>& bytes, size_t offset)
{
	return bytes[offset] | (bytes[offset + 1] << 8) | (bytes[offset + 2] << 16) |
	       (static_cast<uint32_t>(bytes[offset + 3]) << 24);
}

uint16_t read_u16(const std::vector<uint8_t>& bytes, size_t offset)
{
	return static_cast<uint16_t>(bytes[offset] | (bytes[offset + 1] << 8));
}

/*
 * NOISE::load_wav_file() と同じ手順でサンプルを取り出す。
 * fmt の後のチャンクを "data" まで読み飛ばす。
 */
std::vector<int16_t> decode_like_core(const std::vector<uint8_t>& bytes, uint32_t* rate)
{
	std::vector<int16_t> samples;
	if (bytes.size() < 44 || std::memcmp(bytes.data() + 12, "fmt ", 4) != 0 ||
	    read_u16(bytes, 20) != 1 || read_u16(bytes, 22) != 1 || read_u16(bytes, 34) != 16) {
		return samples;
	}
	*rate = read_u32(bytes, 24);
	size_t offset = 20 + read_u32(bytes, 16);
	while (offset + 8 <= bytes.size()) {
		const uint32_t size = read_u32(bytes, offset + 4);
		if (std::memcmp(bytes.data() + offset, "data", 4) == 0) {
			for (size_t i = 0; i + 1 < size && offset + 8 + i + 1 < bytes.size(); i += 2) {
				samples.push_back(static_cast<int16_t>(read_u16(bytes, offset + 8 + i)));
			}
			break;
		}
		offset += 8 + size;
	}
	return samples;
}

std::vector<uint8_t> read_file(const std::string& path)
{
	std::ifstream in(path, std::ios::binary);
	return std::vector<uint8_t>((std::istreambuf_iterator<char>(in)),
	                            std::istreambuf_iterator<char>());
}

void write_file(const std::string& path, const std::string& text)
{
	std::ofstream out(path, std::ios::binary | std::ios::trunc);
	out << text;
}

} // namespace

int main()
{
	group("WAVの形式");
	for (MechanicalNoiseKind kind : bubi::kAllMechanicalNoiseKinds) {
		const std::vector<uint8_t> bytes = bubi::build_mechanical_noise_wav(kind);
		uint32_t rate = 0;
		const std::vector<int16_t> samples = decode_like_core(bytes, &rate);
		std::printf("  %s: %zu samples\n", bubi::mechanical_noise_file_name(kind), samples.size());
		check(!samples.empty() && rate == 44100, "コアと同じ手順で16bit PCMとして読める");
		check(read_u32(bytes, 4) == bytes.size() - 8, "RIFFのサイズが実際の長さと一致する");
		int peak = 0;
		for (int16_t sample : samples) {
			peak = std::max(peak, std::abs(static_cast<int>(sample)));
		}
		check(peak > 1000 && peak < 32767, "無音でも飽和でもない");
		check(bubi::is_generated_mechanical_noise_wav(bytes), "合成物として識別できる");
		check(bytes == bubi::build_mechanical_noise_wav(kind), "毎回同じバイト列になる");
	}

	group("早送り音のループ");
	{
		uint32_t rate = 0;
		const std::vector<int16_t> samples =
		    decode_like_core(bubi::build_mechanical_noise_wav(MechanicalNoiseKind::kCmtFastForward), &rate);
		// 継ぎ目の段差が、ループ内の隣り合うサンプルの最大段差を超えない。
		int max_step = 0;
		for (size_t i = 1; i < samples.size(); ++i) {
			max_step = std::max(max_step, std::abs(samples[i] - samples[i - 1]));
		}
		const int seam = std::abs(samples.front() - samples.back());
		std::printf("  seam=%d max_step=%d\n", seam, max_step);
		check(seam <= max_step, "末尾から先頭へ戻る段差が通常の段差の範囲に収まる");
	}

#if !defined(_WIN32)
	// mkdtemp・symlinkを使うためPOSIXのみ。
	group("core_dirへの配置");
	{
		char templ[] = "/tmp/mechanical_noise_test_XXXXXX";
		const char* made = mkdtemp(templ);
		check(made != nullptr, "作業ディレクトリを作れる");
		const std::string dir = std::string(made) + "/";

		const std::string user_wav = dir + "RELAYOFF.WAV";
		write_file(user_wav, "user relay off");
		bubi::install_generated_mechanical_noise(dir);
		check(bubi::is_generated_mechanical_noise_wav(read_file(dir + "RELAY_ON.WAV")),
		      "無いWAVは合成物を置く");
		check(bubi::is_generated_mechanical_noise_wav(read_file(dir + "FAST_FWD.WAV")),
		      "早送り音も置く");
		check(read_file(user_wav).size() == 14, "利用者のWAVは上書きしない");

		bubi::remove_generated_mechanical_noise(dir);
		struct stat st;
		check(stat((dir + "RELAY_ON.WAV").c_str(), &st) != 0, "合成物は消す");
		check(stat((dir + "FAST_FWD.WAV").c_str(), &st) != 0, "早送り音の合成物も消す");
		check(read_file(user_wav).size() == 14, "利用者のWAVは消さない");

		const std::string target = dir + "user_relay_on.wav";
		write_file(target, "user relay on");
		check(symlink(target.c_str(), (dir + "RELAY_ON.WAV").c_str()) == 0,
		      "ROMディレクトリからの結線を模したリンクを張れる");
		bubi::install_generated_mechanical_noise(dir);
		check(read_file(target).size() == 13, "リンク先の利用者のWAVへ書かない");

		bubi::remove_generated_mechanical_noise(dir);
		unlink((dir + "RELAY_ON.WAV").c_str());
		unlink(target.c_str());
		unlink(user_wav.c_str());

		// シーク音は別名（SEEK.WAV）で置かれていても合成物で塞がない。
		const std::string seek_alias = dir + "SEEK.WAV";
		write_file(seek_alias, "user seek");
		bubi::install_generated_mechanical_noise(dir);
		check(stat((dir + "FDDSEEK.WAV").c_str(), &st) != 0,
		      "SEEK.WAVがあればFDDSEEK.WAVを置かない");
		check(bubi::is_generated_mechanical_noise_wav(read_file(dir + "HEADDOWN.WAV")),
		      "ヘッドロード音は置く");
		bubi::remove_generated_mechanical_noise(dir);
		unlink(seek_alias.c_str());
		check(rmdir(made) == 0, "合成物を残さず片付けられる");
	}
#endif

	if (failures == 0) {
		std::printf("\nすべて合格\n");
		return 0;
	}
	std::printf("\n失敗: %d 件\n", failures);
	return 1;
}
