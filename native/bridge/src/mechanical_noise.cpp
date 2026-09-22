#include "mechanical_noise.h"

#include <sys/stat.h>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iterator>

namespace bubi {

namespace {

constexpr uint32_t kSampleRate = 44100;
constexpr double kPi = 3.14159265358979323846;

// 合成WAVの識別チャンク。upstream NOISE::load_wav_file() は "data" 以外の
// チャンクを読み飛ばすため、fmt と data の間に置いても再生に影響しない。
// 識別はチャンクIDだけで行い、中身（合成方式の版）が変わっても古い
// 合成物を消せるようにする。
constexpr char kMarkerChunkId[4] = {'b', 'u', 'b', 'i'};
constexpr char kMarkerPayload[4] = {'M', 'E', 'C', '1'};
constexpr size_t kMarkerOffset = 12 + 8 + 16; // RIFF + fmtチャンク

// xorshift32。素材を毎回同じにするため固定シードで使う。
class Noise {
public:
	explicit Noise(uint32_t seed) : state_(seed) {}

	double next()
	{
		state_ ^= state_ << 13;
		state_ ^= state_ >> 17;
		state_ ^= state_ << 5;
		return static_cast<double>(state_) / 4294967295.0 * 2.0 - 1.0;
	}

private:
	uint32_t state_;
};

struct Mode {
	double hz;
	double decay_seconds;
	double amplitude;
};

struct Click {
	Mode modes[3];
	double length_seconds;
	double noise_decay_seconds; // 打撃の瞬間のノイズの減衰
	double bounce_seconds;      // 跳ね返りの打撃の時刻（0なら無し）
	double bounce_gain;
	uint32_t seed;
};

/*
 * 機構部品の打撃音（ステッピングモーターの1ステップ、ヘッドやリレーの
 * ソレノイド）。短いノイズバーストと減衰する共振を重ね、跳ね返りとして
 * 少し遅れた小さな打撃をもう1つ足す。
 */
std::vector<double> synth_click(const Click& click)
{
	const size_t length = static_cast<size_t>(click.length_seconds * kSampleRate);
	std::vector<double> out(length, 0.0);
	Noise noise(click.seed);
	const double hits[][2] = {{0.0, 1.0}, {click.bounce_seconds, click.bounce_gain}};
	for (const auto& hit : hits) {
		if (hit[1] <= 0.0) {
			continue;
		}
		const size_t start = static_cast<size_t>(hit[0] * kSampleRate);
		double previous = 0.0;
		for (size_t i = start; i < length; ++i) {
			const double t = static_cast<double>(i - start) / kSampleRate;
			double sample = 0.0;
			for (const Mode& mode : click.modes) {
				sample += mode.amplitude * std::exp(-t / mode.decay_seconds) *
				          std::sin(2.0 * kPi * mode.hz * t);
			}
			// 差分で低域を落としたノイズを、打撃の瞬間だけ鳴らす。
			const double white = noise.next();
			sample += 0.8 * std::exp(-t / click.noise_decay_seconds) * (white - previous);
			previous = white;
			out[i] += hit[1] * sample;
		}
	}
	// 途中で切れて末尾がプツッと鳴らないよう、最後の2msを絞る。
	const size_t fade = std::min(length, static_cast<size_t>(kSampleRate / 500));
	for (size_t i = 0; i < fade; ++i) {
		out[length - 1 - i] *= static_cast<double>(i) / fade;
	}
	return out;
}

/*
 * 早送り・巻戻し中のモーターとテープの走行音。コアがループ再生するため、
 * 周期成分はループ長（1秒）に整数周期で収め、ノイズのフィルターは
 * 2周分回して後半だけを使い、継ぎ目で状態が連続するようにする。
 */
std::vector<double> synth_fast_forward()
{
	const size_t length = kSampleRate; // 1秒でループする
	Noise noise(0x2545f491u);
	std::vector<double> white(length);
	for (double& value : white) {
		value = noise.next();
	}

	// 一次のローパス2段の差で300Hz〜3kHz付近を残す（テープと
	// リールの擦れる音）。
	const double high_cut = 1.0 - std::exp(-2.0 * kPi * 3000.0 / kSampleRate);
	const double low_cut = 1.0 - std::exp(-2.0 * kPi * 300.0 / kSampleRate);
	double high = 0.0;
	double low = 0.0;
	std::vector<double> rustle(length);
	for (size_t i = 0; i < length * 2; ++i) {
		const double input = white[i % length];
		high += high_cut * (input - high);
		low += low_cut * (input - low);
		if (i >= length) {
			rustle[i - length] = high - low;
		}
	}

	std::vector<double> out(length);
	for (size_t i = 0; i < length; ++i) {
		const double t = static_cast<double>(i) / kSampleRate;
		// モーターの唸り（190Hzとその倍音）と、小さな高音のキーン音。
		const double motor = 0.50 * std::sin(2.0 * kPi * 190.0 * t) +
		                     0.25 * std::sin(2.0 * kPi * 380.0 * t) +
		                     0.12 * std::sin(2.0 * kPi * 570.0 * t) +
		                     0.05 * std::sin(2.0 * kPi * 2400.0 * t);
		// リールの回転に合わせたゆっくりした揺れ。
		const double wobble = 1.0 + 0.15 * std::sin(2.0 * kPi * 3.0 * t) +
		                      0.05 * std::sin(2.0 * kPi * 7.0 * t);
		out[i] = wobble * (0.35 * motor + 1.2 * rustle[i]);
	}
	return out;
}

std::vector<int16_t> normalize(const std::vector<double>& samples, double peak)
{
	double max_abs = 0.0;
	for (double value : samples) {
		max_abs = std::max(max_abs, std::fabs(value));
	}
	const double scale = max_abs > 0.0 ? peak / max_abs : 0.0;
	std::vector<int16_t> out(samples.size());
	for (size_t i = 0; i < samples.size(); ++i) {
		out[i] = static_cast<int16_t>(std::lround(samples[i] * scale));
	}
	return out;
}

void put_u16(std::vector<uint8_t>& bytes, uint16_t value)
{
	bytes.push_back(static_cast<uint8_t>(value & 0xff));
	bytes.push_back(static_cast<uint8_t>(value >> 8));
}

void put_u32(std::vector<uint8_t>& bytes, uint32_t value)
{
	put_u16(bytes, static_cast<uint16_t>(value & 0xffff));
	put_u16(bytes, static_cast<uint16_t>(value >> 16));
}

void put_id(std::vector<uint8_t>& bytes, const char (&id)[4])
{
	bytes.insert(bytes.end(), id, id + 4);
}

std::vector<uint8_t> encode_wav(const std::vector<int16_t>& samples)
{
	const uint32_t data_size = static_cast<uint32_t>(samples.size() * 2);
	std::vector<uint8_t> bytes;
	bytes.reserve(kMarkerOffset + 12 + 8 + data_size);
	put_id(bytes, {'R', 'I', 'F', 'F'});
	put_u32(bytes, 4 + (8 + 16) + (8 + 4) + (8 + data_size));
	put_id(bytes, {'W', 'A', 'V', 'E'});
	put_id(bytes, {'f', 'm', 't', ' '});
	put_u32(bytes, 16);
	put_u16(bytes, 1); // PCM
	put_u16(bytes, 1); // モノラル
	put_u32(bytes, kSampleRate);
	put_u32(bytes, kSampleRate * 2);
	put_u16(bytes, 2);
	put_u16(bytes, 16);
	put_id(bytes, kMarkerChunkId);
	put_u32(bytes, 4);
	put_id(bytes, kMarkerPayload);
	put_id(bytes, {'d', 'a', 't', 'a'});
	put_u32(bytes, data_size);
	for (int16_t sample : samples) {
		put_u16(bytes, static_cast<uint16_t>(sample));
	}
	return bytes;
}

// シンボリックリンクは辿らずに有無を調べる。壊れたリンクへ書くと
// リンク先（利用者のROMディレクトリ）にファイルを作ってしまうため。
bool path_exists(const std::string& path)
{
	struct stat st;
#if defined(_WIN32)
	return stat(path.c_str(), &st) == 0;
#else
	return lstat(path.c_str(), &st) == 0;
#endif
}

bool is_symlink(const std::string& path)
{
#if defined(_WIN32)
	(void)path;
	return false;
#else
	struct stat st;
	return lstat(path.c_str(), &st) == 0 && S_ISLNK(st.st_mode);
#endif
}

} // namespace

const MechanicalNoiseKind kAllMechanicalNoiseKinds[6] = {
    MechanicalNoiseKind::kFddSeek,      MechanicalNoiseKind::kFddHeadDown,
    MechanicalNoiseKind::kFddHeadUp,    MechanicalNoiseKind::kCmtRelayOn,
    MechanicalNoiseKind::kCmtRelayOff,  MechanicalNoiseKind::kCmtFastForward,
};

const char* mechanical_noise_file_name(MechanicalNoiseKind kind)
{
	switch (kind) {
	case MechanicalNoiseKind::kFddSeek:
		return "FDDSEEK.WAV";
	case MechanicalNoiseKind::kFddHeadDown:
		return "HEADDOWN.WAV";
	case MechanicalNoiseKind::kFddHeadUp:
		return "HEADUP.WAV";
	case MechanicalNoiseKind::kCmtRelayOn:
		return "RELAY_ON.WAV";
	case MechanicalNoiseKind::kCmtRelayOff:
		return "RELAYOFF.WAV";
	case MechanicalNoiseKind::kCmtFastForward:
		return "FAST_FWD.WAV";
	}
	return "";
}

std::vector<uint8_t> build_mechanical_noise_wav(MechanicalNoiseKind kind)
{
	switch (kind) {
	case MechanicalNoiseKind::kFddSeek:
		// MB8877はトラックを1つ動かすたびに鳴らし、鳴り終わるまでは次を
		// 鳴らさない（NOISE::play()）。ステップ間隔（6ms〜）に近い長さにする。
		return encode_wav(normalize(
		    synth_click({{{230.0, 0.004, 1.0}, {1100.0, 0.0015, 0.5}, {3200.0, 0.0008, 0.3}},
		                 0.010, 0.0006, 0.0, 0.0, 0x1b873593u}),
		    9000.0));
	case MechanicalNoiseKind::kFddHeadDown:
		return encode_wav(normalize(
		    synth_click({{{900.0, 0.006, 1.0}, {2200.0, 0.003, 0.5}, {160.0, 0.015, 0.7}},
		                 0.060, 0.002, 0.006, 0.3, 0xcc9e2d51u}),
		    10000.0));
	case MechanicalNoiseKind::kFddHeadUp:
		return encode_wav(normalize(
		    synth_click({{{750.0, 0.005, 1.0}, {1900.0, 0.0025, 0.4}, {140.0, 0.012, 0.5}},
		                 0.045, 0.0015, 0.0, 0.0, 0xe6546b64u}),
		    7000.0));
	case MechanicalNoiseKind::kCmtRelayOn:
		return encode_wav(normalize(
		    synth_click({{{1800.0, 0.004, 1.0}, {3900.0, 0.002, 0.6}, {450.0, 0.012, 0.5}},
		                 0.080, 0.0015, 0.007, 0.35, 0x9e3779b9u}),
		    14000.0));
	case MechanicalNoiseKind::kCmtRelayOff:
		return encode_wav(normalize(
		    synth_click({{{1500.0, 0.004, 1.0}, {3300.0, 0.002, 0.5}, {380.0, 0.010, 0.5}},
		                 0.080, 0.0015, 0.005, 0.35, 0x85ebca6bu}),
		    11000.0));
	case MechanicalNoiseKind::kCmtFastForward:
		return encode_wav(normalize(synth_fast_forward(), 7000.0));
	}
	return {};
}

bool is_generated_mechanical_noise_wav(const std::vector<uint8_t>& bytes)
{
	return bytes.size() >= kMarkerOffset + 12 &&
	       std::memcmp(bytes.data(), "RIFF", 4) == 0 &&
	       std::memcmp(bytes.data() + kMarkerOffset, kMarkerChunkId, 4) == 0;
}

void remove_generated_mechanical_noise(const std::string& core_dir)
{
	for (MechanicalNoiseKind kind : kAllMechanicalNoiseKinds) {
		const std::string path = core_dir + mechanical_noise_file_name(kind);
		// リンクは結線側が張り直すので触らない（辿って読むのも避ける）。
		if (!path_exists(path) || is_symlink(path)) {
			continue;
		}
		std::ifstream in(path, std::ios::binary);
		const std::vector<uint8_t> bytes(
		    (std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
		in.close();
		if (is_generated_mechanical_noise_wav(bytes)) {
			std::remove(path.c_str());
		}
	}
}

void install_generated_mechanical_noise(const std::string& core_dir)
{
	for (MechanicalNoiseKind kind : kAllMechanicalNoiseKinds) {
		const std::string path = core_dir + mechanical_noise_file_name(kind);
		if (path_exists(path)) {
			continue; // 利用者のWAV（ROMディレクトリからの結線）を優先する
		}
		// シーク音はFDDSEEK.WAVが無いときFDDSEEK1.WAV、SEEK.WAVの順に読まれる。
		// 利用者がそちらの名前で置いていれば合成物で塞がない。
		if (kind == MechanicalNoiseKind::kFddSeek &&
		    (path_exists(core_dir + "FDDSEEK1.WAV") || path_exists(core_dir + "SEEK.WAV"))) {
			continue;
		}
		const std::vector<uint8_t> bytes = build_mechanical_noise_wav(kind);
		std::ofstream out(path, std::ios::binary | std::ios::trunc);
		out.write(reinterpret_cast<const char*>(bytes.data()),
		          static_cast<std::streamsize>(bytes.size()));
	}
}

} // namespace bubi
