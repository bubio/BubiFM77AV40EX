/*
 * FDD・CMT機構音（AUD-04、AUD-07）の素材WAVの合成。
 *
 * upstreamはFDDのシーク音・ヘッドロード／アンロード音（MB8877::initialize()）
 * と、CMTのリレー音・早送り音（DATAREC::initialize()）を
 * get_application_path()（= core_dir）のWAVから読み、無ければ黙って鳴らさない。
 * 素材は配布されていないため、ブリッジがVM生成前に合成したWAVを core_dir へ
 * 置く。鳴らすタイミング・ミュート・音量はコア側（MB8877のシーク・ヘッド
 * 状態、DATAREC::set_remote/set_ff_rew、config.sound_noise_fdd/
 * sound_noise_cmt、音量ch9/ch10）のまま変えない。
 *
 * 利用者がROMディレクトリに同名のWAVを置いた場合はそちらを優先する。
 * 合成したWAVは専用チャンクで識別し、利用者のファイルと区別する。
 */
#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace bubi {

enum class MechanicalNoiseKind {
	kFddSeek,
	kFddHeadDown,
	kFddHeadUp,
	kCmtRelayOn,
	kCmtRelayOff,
	kCmtFastForward,
};

extern const MechanicalNoiseKind kAllMechanicalNoiseKinds[6];

// コアが開くファイル名（mb8877.cpp・datarec.cpp の load_wav_file の引数と同じ）。
const char* mechanical_noise_file_name(MechanicalNoiseKind kind);

// 合成したWAV（PCM 16bit・モノラル）のファイル内容。毎回同じバイト列を返す。
std::vector<uint8_t> build_mechanical_noise_wav(MechanicalNoiseKind kind);

// bytes が build_mechanical_noise_wav() の生成物であれば true。
bool is_generated_mechanical_noise_wav(const std::vector<uint8_t>& bytes);

/*
 * core_dir に残っている合成WAVを消す。ROMディレクトリの結線
 * （wire_rom_directory）より前に呼ぶ。残したままだと、利用者が後から
 * 置いたWAVへのリンクが「既にファイルがある」として張られない。
 */
void remove_generated_mechanical_noise(const std::string& core_dir);

/*
 * core_dir に無い機構音WAVだけを合成して書く。結線の後、VM生成の前に
 * 呼ぶ。書けなかった場合もコアは無音になるだけなので失敗は返さない。
 */
void install_generated_mechanical_noise(const std::string& core_dir);

} // namespace bubi
