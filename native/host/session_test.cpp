/*
 * 製品用 C ABI（native/bridge/）の検査本体。
 * development_plan.md 6 WP1 の4項目に対応する。
 *
 *   1. C ABIでcreate/start/stop/destroyと通常／特殊リセットを実装する
 *   2. Core threadだけがVMを操作することをテストする
 *   3. 二重開始、停止中の操作、初期化失敗、破棄の冪等性を検証する
 *   4. コマンドID、イベント、エラー型を定義する
 *
 * ROMを必要とせず、CIで実行できる。リーク検査は本体では行わず、
 * scripts/run_native_checks.sh が macOS の leaks(1) で外側から判定する。
 */
#include <dirent.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <set>
#include <string>
#include <thread>
#include <vector>

#include "bubi_fm77av.h"

#ifdef BUBI_ENABLE_TEST_HOOKS
extern "C" void bfm_test_touch_vm_guard_from_caller_thread(bfm_session* session);
#endif

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

std::string g_home;

bfm_session* make_session(const char* home = nullptr, uint32_t command_capacity = 0,
                          uint32_t event_capacity = 0, const char* rom_dir = nullptr)
{
	bfm_create_options options{};
	options.home_dir = (home != nullptr) ? home : g_home.c_str();
	options.rom_dir = rom_dir;
	options.command_queue_capacity = command_capacity;
	options.event_queue_capacity = event_capacity;

	bfm_session* session = nullptr;
	if (bfm_create(&options, &session) != BFM_OK) {
		return nullptr;
	}
	return session;
}

// --- ROM結線の検査で使うファイル操作 ---

bool write_file(const std::string& path, const std::string& content)
{
	FILE* fp = fopen(path.c_str(), "wb");
	if (fp == nullptr) {
		return false;
	}
	const bool ok = content.empty()
	    || fwrite(content.data(), 1, content.size(), fp) == content.size();
	fclose(fp);
	return ok;
}

std::string read_file(const std::string& path)
{
	FILE* fp = fopen(path.c_str(), "rb");
	if (fp == nullptr) {
		return std::string();
	}
	std::string out;
	char buffer[256];
	for (;;) {
		const size_t read = fread(buffer, 1, sizeof(buffer), fp);
		out.append(buffer, read);
		if (read < sizeof(buffer)) {
			break;
		}
	}
	fclose(fp);
	return out;
}

bool is_symlink_to(const std::string& path, const std::string& target)
{
	struct stat st;
	if (lstat(path.c_str(), &st) != 0 || !S_ISLNK(st.st_mode)) {
		return false;
	}
	char resolved[4096];
	const ssize_t length = readlink(path.c_str(), resolved, sizeof(resolved) - 1);
	if (length < 0) {
		return false;
	}
	resolved[length] = '\0';
	return target == resolved;
}

bool is_regular_file(const std::string& path)
{
	struct stat st;
	return lstat(path.c_str(), &st) == 0 && S_ISREG(st.st_mode);
}

/*
 * BIOS不要の最小D88（development_plan.md WP5「BIOS不要の公開可能な最小
 * テストイメージ」）。トラックを1つも持たない空ディスクで、レイアウトは
 * upstream の EMU::create_blank_floppy_disk（emu.cpp）と同じにする。
 * 資産をコミットせず、テストコードでその場に作る。
 */
bool write_blank_d88(const std::string& path, bool protect = false)
{
	std::string header;
	header.append("BLANK", 5);
	header.append(17 - 5, '\0');           // title[17]
	header.append(9, '\0');                // rsrv[9]
	header.push_back(protect ? 0x10 : 0);  // protect（vm/disk.cppはbuffer[0x1a]!=0を見る）
	header.push_back('\0');                // type = MEDIA_TYPE_2D
	const uint32_t size = static_cast<uint32_t>(17 + 9 + 1 + 1 + 4 + 164 * 4);
	header.append(reinterpret_cast<const char*>(&size), sizeof(size));
	header.append(164 * 4, '\0'); // trkptr[164]、全トラック未使用
	return write_file(path, header);
}

std::string core_directory_of(bfm_session* session)
{
	char buffer[4096];
	if (bfm_get_core_directory(session, buffer, sizeof(buffer)) != BFM_OK) {
		return std::string();
	}
	return std::string(buffer);
}

bool wait_for_state(bfm_session* session, bfm_state expected, int timeout_ms)
{
	for (int i = 0; i < timeout_ms; ++i) {
		if (bfm_get_state(session) == static_cast<int32_t>(expected)) {
			return true;
		}
		std::this_thread::sleep_for(std::chrono::milliseconds(1));
	}
	return false;
}

// フレーム数が baseline を超えるまで待つ。
//
// 「一定時間眠って数える」方式にすると、負荷の高いCIランナーで
// スケジューリングに負けて偽陽性になる。時間ではなく条件で待つ。
bool wait_for_frames_beyond(bfm_session* session, uint64_t baseline, int timeout_ms)
{
	for (int i = 0; i < timeout_ms; ++i) {
		bfm_stats stats{};
		if (bfm_get_stats(session, &stats) == BFM_OK && stats.frames_run > baseline) {
			return true;
		}
		std::this_thread::sleep_for(std::chrono::milliseconds(1));
	}
	return false;
}

// 指定IDの completed イベントを待つ。見つかれば code を out_code へ返す。
bool wait_for_completion(bfm_session* session, uint64_t id, int timeout_ms, int32_t* out_code)
{
	for (int i = 0; i < timeout_ms; ++i) {
		bfm_event event{};
		while (bfm_poll_event(session, &event) == BFM_OK) {
			if (event.kind == BFM_EVENT_COMMAND_COMPLETED && event.command_id == id) {
				if (out_code != nullptr) {
					*out_code = event.code;
				}
				return true;
			}
		}
		std::this_thread::sleep_for(std::chrono::milliseconds(1));
	}
	return false;
}

// --- 1. 引数検証と所有権 ---
void test_argument_validation()
{
	group("引数検証と所有権");

	bfm_session* session = nullptr;
	check(bfm_create(nullptr, &session) == BFM_ERR_INVALID_ARGUMENT,
	      "options が NULL なら invalidArgument");
	check(session == nullptr, "失敗時に out を書き換えない");

	bfm_create_options options{};
	options.home_dir = g_home.c_str();
	check(bfm_create(&options, nullptr) == BFM_ERR_INVALID_ARGUMENT,
	      "out が NULL なら invalidArgument");

	bfm_create_options empty{};
	empty.home_dir = "";
	check(bfm_create(&empty, &session) == BFM_ERR_INVALID_ARGUMENT,
	      "home_dir が空なら invalidArgument");

	bfm_destroy(nullptr); // 落ちないこと
	check(true, "bfm_destroy(NULL) は無害");

	check(bfm_get_state(nullptr) == BFM_STATE_STOPPED, "NULLハンドルの状態は stopped");
	check(bfm_start(nullptr) == BFM_ERR_INVALID_ARGUMENT, "NULLハンドルの start を拒否");
	check(bfm_stop(nullptr) == BFM_ERR_INVALID_ARGUMENT, "NULLハンドルの stop を拒否");
	check(bfm_poll_event(nullptr, nullptr) == BFM_ERR_INVALID_ARGUMENT,
	      "NULLハンドルの poll を拒否");
	check(bfm_get_stats(nullptr, nullptr) == BFM_ERR_INVALID_ARGUMENT,
	      "NULLハンドルの stats を拒否");
}

// --- 2. ライフサイクルと冪等性 ---
void test_lifecycle()
{
	group("ライフサイクルと冪等性");

	bfm_session* session = make_session();
	check(session != nullptr, "生成できる");
	if (session == nullptr) {
		return;
	}

	check(bfm_get_state(session) == BFM_STATE_STOPPED, "生成直後は stopped");
	check(bfm_reset(session, BFM_RESET_NORMAL, nullptr) == BFM_ERR_INVALID_STATE,
	      "停止中のリセットは invalidState");

	bfm_command command{};
	command.kind = BFM_CMD_RESET;
	check(bfm_send_command(session, &command, nullptr) == BFM_ERR_INVALID_STATE,
	      "停止中のコマンドは invalidState");

	bfm_event event{};
	check(bfm_poll_event(session, &event) == BFM_ERR_NO_EVENT,
	      "未起動のセッションにイベントはない");

	check(bfm_start(session) == BFM_OK, "起動できる");
	check(bfm_start(session) == BFM_ERR_INVALID_STATE, "二重起動を拒否する");
	check(wait_for_state(session, BFM_STATE_RUNNING, 5000), "running へ遷移する");

	check(bfm_stop(session) == BFM_OK, "停止できる");
	check(bfm_stop(session) == BFM_OK, "停止は冪等");
	check(bfm_get_state(session) == BFM_STATE_STOPPED, "停止後は stopped");

	bfm_stats stats{};
	check(bfm_get_stats(session, &stats) == BFM_OK, "統計を取得できる");
	check(stats.frames_run > 0, "Core threadがフレームを進めた");

	bfm_destroy(session);
	check(true, "破棄できる");
}

// --- 3. 生成から破棄までの反復 ---
void test_repeated_cycles()
{
	group("生成から破棄までの反復");

	const int cycles = 20;
	bool every_cycle_advanced = true;
	bool all_ok = true;

	for (int i = 0; i < cycles; ++i) {
		bfm_session* session = make_session();
		if (session == nullptr) {
			all_ok = false;
			break;
		}
		if (bfm_start(session) != BFM_OK
			|| !wait_for_state(session, BFM_STATE_RUNNING, 5000)) {
			all_ok = false;
			bfm_destroy(session);
			break;
		}

		uint64_t id = 0;
		if (bfm_reset(session, BFM_RESET_NORMAL, &id) != BFM_OK) {
			all_ok = false;
		}

		bfm_stats stats{};
		bfm_get_stats(session, &stats);
		if (!wait_for_frames_beyond(session, stats.frames_run, 5000)) {
			every_cycle_advanced = false;
		}

		bfm_stop(session);
		bfm_destroy(session);
	}

	check(all_ok, "20回の生成・起動・停止・破棄が成功する");
	check(every_cycle_advanced, "すべての回でフレームが進む");
}

// --- 4. コマンドIDとイベントの対応、リセット種別 ---
void test_command_events()
{
	group("コマンドIDとイベントの対応");

	bfm_session* session = make_session();
	if (session == nullptr) {
		check(false, "生成できる");
		return;
	}
	bfm_start(session);
	check(wait_for_state(session, BFM_STATE_RUNNING, 5000), "running へ遷移する");

	uint64_t normal_id = 0;
	check(bfm_reset(session, BFM_RESET_NORMAL, &normal_id) == BFM_OK, "通常リセットを投入できる");
	check(normal_id != 0, "連番IDが返る");

	uint64_t special_id = 0;
	check(bfm_reset(session, BFM_RESET_SPECIAL, &special_id) == BFM_OK,
	      "特殊リセットを投入できる");
	check(special_id > normal_id, "IDは単調増加する");

	int32_t code = -1;
	check(wait_for_completion(session, normal_id, 5000, &code), "通常リセットの完了通知が届く");
	check(code == BFM_OK, "通常リセットは成功で完了する");

	code = -1;
	check(wait_for_completion(session, special_id, 5000, &code), "特殊リセットの完了通知が届く");
	check(code == BFM_OK, "特殊リセットは成功で完了する");

	check(bfm_reset(session, static_cast<bfm_reset_kind>(99), nullptr)
	          == BFM_ERR_INVALID_ARGUMENT,
	      "未定義のリセット種別は invalidArgument");

	// 型として定義済みだが未実装（M7以降）のコマンドは unsupported で完了する。
	// BFM_CMD_INSERT_FDD/EJECT_FDD、SET_FDD_WRITE_PROTECT/TIMING/CRC_CHECKは
	// M3で実装済みのため test_media() で検査する。
	bfm_command mouse{};
	mouse.kind = BFM_CMD_MOUSE;
	uint64_t unsupported_id = 0;
	check(bfm_send_command(session, &mouse, &unsupported_id) == BFM_OK,
	      "未実装コマンドも受け付ける");
	code = -1;
	check(wait_for_completion(session, unsupported_id, 5000, &code), "未実装コマンドの完了通知が届く");
	check(code == BFM_ERR_UNSUPPORTED, "未実装コマンドは unsupported で完了する");

	bfm_stop(session);
	bfm_destroy(session);
}

// --- 5. Core threadだけがVMを操作する ---
void test_core_thread_ownership()
{
	group("Core threadだけがVMを操作する");

	bfm_session* session = make_session();
	if (session == nullptr) {
		check(false, "生成できる");
		return;
	}
	bfm_start(session);
	check(wait_for_state(session, BFM_STATE_RUNNING, 5000), "running へ遷移する");

	uint64_t id = 0;
	bfm_reset(session, BFM_RESET_SPECIAL, &id);
	wait_for_completion(session, id, 5000, nullptr);
	std::this_thread::sleep_for(std::chrono::milliseconds(50));

	bfm_stats stats{};
	bfm_get_stats(session, &stats);
	check(stats.vm_access_violations == 0,
	      "生成・run・コマンド適用・破棄がすべてCore threadから行われた");

#ifdef BUBI_ENABLE_TEST_HOOKS
	// 見張りそのものが機能していることを確かめる。
	// VMには触れずガードだけを呼ぶので、実際のデータ競合は起こさない。
	bfm_test_touch_vm_guard_from_caller_thread(session);
	bfm_stats after{};
	bfm_get_stats(session, &after);
	check(after.vm_access_violations == stats.vm_access_violations + 1,
	      "Core thread以外からの侵入を見張りが検出する");
#else
	check(false, "テストフック（BUBI_ENABLE_TEST_HOOKS）が有効でない");
#endif

	bfm_stop(session);
	bfm_destroy(session);
}

// --- 6. 初期化失敗 ---
//
// home_dir はプロセス全体で1つに固定されるため、書込み不能な home_dir の
// 検査は別プロセス（--unwritable-home）で行う。ここでは同じ home_dir のまま
// 失敗させられる経路として、存在しないROMディレクトリを使う。
void test_initialization_failure()
{
	group("初期化失敗");

	bfm_session* session = make_session(nullptr, 0, 0, "/dev/null/no-such-rom-dir");
	check(session != nullptr, "生成自体は成功する（失敗はCore threadで判明する）");
	if (session == nullptr) {
		return;
	}

	check(bfm_start(session) == BFM_OK, "起動要求は受理される");

	// STARTING の間に受理できたコマンドを覚えておく。失敗しても未完了で
	// 残してはならない。窓が短いため0件のこともあり、その場合は検査しない。
	std::vector<uint64_t> accepted;
	while (bfm_get_state(session) == BFM_STATE_STARTING) {
		uint64_t id = 0;
		if (bfm_reset(session, BFM_RESET_NORMAL, &id) != BFM_OK) {
			break;
		}
		accepted.push_back(id);
	}

	check(wait_for_state(session, BFM_STATE_FAILED, 5000), "failed へ遷移する");

	bool saw_error = false;
	std::set<uint64_t> completed;
	bfm_event event{};
	while (bfm_poll_event(session, &event) == BFM_OK) {
		if (event.kind == BFM_EVENT_ERROR && event.code == BFM_ERR_CORE_FAILED) {
			saw_error = true;
		}
		if (event.kind == BFM_EVENT_COMMAND_COMPLETED) {
			completed.insert(event.command_id);
		}
	}
	check(saw_error, "coreFailed のエラーイベントを通知する");

	if (accepted.empty()) {
		std::printf("  [skip] 初期化失敗前にコマンドを受理する窓がなかった\n");
	} else {
		bool all_completed = true;
		for (const uint64_t id : accepted) {
			if (completed.find(id) == completed.end()) {
				all_completed = false;
			}
		}
		check(all_completed, "初期化失敗時も受理済みコマンドを完了させる");
	}

	check(bfm_reset(session, BFM_RESET_NORMAL, nullptr) == BFM_ERR_INVALID_STATE,
	      "failed 状態のコマンドは invalidState");
	check(bfm_stop(session) == BFM_OK, "failed からも停止できる");

	bfm_destroy(session);
	check(true, "failed 状態から破棄できる");
}

// --- 7. コマンドキューの飽和 ---
void test_command_queue_saturation()
{
	group("コマンドキューの飽和");

	bfm_session* session = make_session(nullptr, 4, 0);
	if (session == nullptr) {
		check(false, "生成できる");
		return;
	}
	bfm_start(session);
	check(wait_for_state(session, BFM_STATE_RUNNING, 5000), "running へ遷移する");

	// Core threadはフレーム毎にしか引き取らない。連続投入で必ず飽和する。
	bool saw_queue_full = false;
	std::vector<uint64_t> accepted;
	for (int i = 0; i < 200; ++i) {
		uint64_t id = 0;
		const bfm_result result = bfm_reset(session, BFM_RESET_NORMAL, &id);
		if (result == BFM_ERR_QUEUE_FULL) {
			saw_queue_full = true;
			break;
		}
		if (result == BFM_OK) {
			accepted.push_back(id);
		}
	}
	check(saw_queue_full, "飽和時は新しいコマンドを拒否する");

	bfm_stats stats{};
	bfm_get_stats(session, &stats);
	check(stats.commands_rejected > 0, "拒否数を統計で観測できる");

	check(bfm_stop(session) == BFM_OK, "飽和中でも停止できる");

	// 受理したコマンドを完了通知なしに捨てない。捨てると、同じIDの
	// 完了を待つ呼び出し側が永久に待つ。
	std::set<uint64_t> completed;
	bfm_event event{};
	while (bfm_poll_event(session, &event) == BFM_OK) {
		if (event.kind == BFM_EVENT_COMMAND_COMPLETED) {
			completed.insert(event.command_id);
		}
	}
	bool all_completed = !accepted.empty();
	for (const uint64_t id : accepted) {
		if (completed.find(id) == completed.end()) {
			all_completed = false;
		}
	}
	check(all_completed, "受理したコマンドは停止後もすべて完了通知が届く");

	bfm_destroy(session);
}

// --- 8. UIがイベントを引き取らない場合 ---
void test_ui_stall()
{
	group("UIがイベントを引き取らない場合");

	bfm_session* session = make_session(nullptr, 0, 4);
	if (session == nullptr) {
		check(false, "生成できる");
		return;
	}
	bfm_start(session);
	check(wait_for_state(session, BFM_STATE_RUNNING, 5000), "running へ遷移する");

	// 一度も poll しないままコマンドを流し、イベントキューを溢れさせる。
	for (int i = 0; i < 20; ++i) {
		bfm_reset(session, BFM_RESET_NORMAL, nullptr);
		std::this_thread::sleep_for(std::chrono::milliseconds(20));
	}

	bfm_stats stats{};
	bfm_get_stats(session, &stats);
	check(stats.events_dropped > 0, "古いイベントから捨てる");
	check(stats.frames_run > 0, "イベントを捨てつつコアは進み続ける");

	check(bfm_stop(session) == BFM_OK, "UI停止中でも停止できる");
	bfm_destroy(session);
}

// --- 9. 生存セッションは1つ ---
void test_single_live_session()
{
	group("生存セッションの制限");

	bfm_session* first = make_session();
	check(first != nullptr, "1つ目を生成できる");

	bfm_session* second = make_session();
	check(second == nullptr, "2つ目は拒否する（cpp_homedir がプロセス全域のため）");

	bfm_destroy(first);
	bfm_session* third = make_session();
	check(third != nullptr, "破棄後は再び生成できる");
	bfm_destroy(third);
}

/* 名前を大小文字を区別して探す。macOSの既定は区別しないため、
 * パスで開く検査では大文字の別名の有無を判定できない。 */
bool directory_has_exact_name(const std::string& directory, const std::string& name)
{
	DIR* dir = opendir(directory.c_str());
	if (dir == nullptr) {
		return false;
	}
	bool found = false;
	for (struct dirent* entry = readdir(dir); entry != nullptr; entry = readdir(dir)) {
		if (name == entry->d_name) {
			found = true;
			break;
		}
	}
	closedir(dir);
	return found;
}

// --- 10. ROMディレクトリの結線 ---
void test_rom_wiring()
{
	group("ROMディレクトリの結線");

	const std::string rom_a = g_home + "/rom-a";
	const std::string rom_b = g_home + "/rom-b";
	mkdir(rom_a.c_str(), 0700);
	mkdir(rom_b.c_str(), 0700);
	mkdir((rom_a + "/subdir").c_str(), 0700);

	// 本物のROMは要らない。名前と存在だけを見る結線の検査である。
	check(write_file(rom_a + "/INITIATE.ROM", std::string(8192, '\0')),
	      "ダミーROMを用意できる");
	check(write_file(rom_a + "/SUBSYS_A.ROM", std::string(8192, '\0')),
	      "2つ目のダミーROMを用意できる");
	// 利用者のROMディレクトリにコアの書込み対象と同名のファイルがある場合。
	check(write_file(rom_a + "/USERDIC.DAT", "利用者のROMディレクトリ側"),
	      "同名の書込み対象ファイルを用意できる");
	// 利用者のファイル名が小文字のことがある。コアは大文字で開くので、
	// 大文字化した別名も張られなければ、大小文字を区別するファイルシステム
	// （Linux）でROMを1つも読めなくなる。
	check(write_file(rom_a + "/SUBSYS_B.rom", std::string(8192, '\0')),
	      "小文字のダミーROMを用意できる");
	check(write_file(rom_b + "/EXTSUB.ROM", std::string(49152, '\0')),
	      "別ディレクトリのダミーROMを用意できる");

	bfm_session* session = make_session(nullptr, 0, 0, rom_a.c_str());
	if (session == nullptr) {
		check(false, "生成できる");
		return;
	}

	const std::string core_dir = core_directory_of(session);
	check(!core_dir.empty(), "コアの読込みディレクトリを取得できる");

	// コアが書く USERDIC.DAT と、コアが触らない実体ファイルを置く。
	// どちらも張り直しで消えてはならない。
	const std::string learn_data = core_dir + "USERDIC.DAT";
	const std::string keep_me = core_dir + "keep-me.dat";
	const std::string keep_content = "張り直しで消えてはならない実体ファイル";
	check(write_file(learn_data, "既存の辞書学習データ"), "既存の USERDIC.DAT を用意できる");
	check(write_file(keep_me, keep_content), "コアが触らない実体ファイルを用意できる");

	bfm_start(session);
	check(wait_for_state(session, BFM_STATE_RUNNING, 5000), "running へ遷移する");

	check(is_symlink_to(core_dir + "INITIATE.ROM", rom_a + "/INITIATE.ROM"),
	      "ROMへシンボリックリンクを張る");
	check(is_symlink_to(core_dir + "SUBSYS_A.ROM", rom_a + "/SUBSYS_A.ROM"),
	      "複数のROMを張る");
	check(!is_symlink_to(core_dir + "subdir", rom_a + "/subdir"),
	      "ディレクトリは張らない");
	// 名前は大小文字を区別して確かめる。macOSの既定は区別しないため、
	// パスで開く検査では大文字の別名がなくても通ってしまう。
	check(directory_has_exact_name(core_dir, "SUBSYS_B.rom"),
	      "小文字のROMを元の名前で張る");
	// コアは大文字の名前で開く。macOSでは小文字のリンク1本で解決でき、
	// Linuxでは大文字の別名が要る。ここでは結果だけを見る。
	check(is_symlink_to(core_dir + "SUBSYS_B.ROM", rom_a + "/SUBSYS_B.rom"),
	      "小文字のROMを大文字の名前で開ける");
	// コアは USERDIC.DAT を自分で書き直す。守るべきなのは中身ではなく、
	// 「リンクにしないこと」と「利用者のROMディレクトリへ書かせないこと」。
	check(is_regular_file(learn_data), "USERDIC.DAT をリンクに置き換えない");
	check(read_file(rom_a + "/USERDIC.DAT") == "利用者のROMディレクトリ側",
	      "利用者のROMディレクトリへ書き込ませない");

	bfm_stop(session);
	bfm_destroy(session);

	// 別のROMディレクトリへ張り直す。
	bfm_session* second = make_session(nullptr, 0, 0, rom_b.c_str());
	if (second == nullptr) {
		check(false, "2回目の生成ができる");
		return;
	}
	bfm_start(second);
	check(wait_for_state(second, BFM_STATE_RUNNING, 5000), "張り直し後も running になる");

	check(!is_symlink_to(core_dir + "INITIATE.ROM", rom_a + "/INITIATE.ROM"),
	      "古いリンクを外す");
	check(is_symlink_to(core_dir + "EXTSUB.ROM", rom_b + "/EXTSUB.ROM"),
	      "新しいリンクを張る");
	check(is_regular_file(learn_data), "張り直しでも USERDIC.DAT を消さない");
	check(is_regular_file(keep_me) && read_file(keep_me) == keep_content,
	      "張り直しで通常ファイルを消さない");

	bfm_stop(second);
	bfm_destroy(second);
}

// --- 11. ブートモード ---
void test_boot_mode()
{
	group("ブートモード");

	bfm_create_options options{};
	options.home_dir = g_home.c_str();
	options.boot_mode = 99;
	bfm_session* invalid = nullptr;
	check(bfm_create(&options, &invalid) == BFM_ERR_INVALID_ARGUMENT,
	      "未定義のブートモードは invalidArgument");

	bfm_session* session = make_session();
	if (session == nullptr) {
		check(false, "生成できる");
		return;
	}
	bfm_start(session);
	check(wait_for_state(session, BFM_STATE_RUNNING, 5000), "running へ遷移する");

	bfm_command command{};
	command.kind = BFM_CMD_SET_BOOT_MODE;
	command.arg0 = BFM_BOOT_DOS;
	uint64_t id = 0;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "DOSブートを投入できる");
	int32_t code = -1;
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	check(code == BFM_OK, "ブートモードの変更が成功で完了する");

	command.arg0 = 42;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "不正値も受理はする");
	code = -1;
	check(wait_for_completion(session, id, 5000, &code), "不正値の完了通知が届く");
	check(code == BFM_ERR_INVALID_ARGUMENT, "不正なブートモードは invalidArgument で完了");

	bfm_stop(session);
	bfm_destroy(session);
}

// --- 11.1 実行設定（SYS-03、SYS-05、SYS-06） ---
void test_run_settings()
{
	group("実行設定（速度・CPU種別・オプションスイッチ）");

	bfm_session* session = make_session();
	if (session == nullptr) {
		check(false, "生成できる");
		return;
	}
	bfm_start(session);
	check(wait_for_state(session, BFM_STATE_RUNNING, 5000), "running へ遷移する");

	bfm_command command{};
	uint64_t id = 0;
	int32_t code = -1;

	// 速度倍率（SYS-03）。
	command = bfm_command{};
	command.kind = BFM_CMD_SET_SPEED_MULTIPLIER;
	command.arg0 = 4; // x16
	check(bfm_send_command(session, &command, &id) == BFM_OK, "x16を投入できる");
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	check(code == BFM_OK, "範囲内の速度倍率が成功で完了する");

	command.arg0 = 5;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "範囲外も受理はする");
	code = -1;
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	check(code == BFM_ERR_INVALID_ARGUMENT, "範囲外の速度倍率は invalidArgument");

	command.arg0 = 0; // x1に戻す
	check(bfm_send_command(session, &command, &id) == BFM_OK, "x1に戻せる");
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");

	// 速度倍率（config.cpu_power）はCore threadがvm->run()を呼ぶ間隔
	// （壁時計、frame_period）自体を変えない。x1とx16でframes_run
	// （vm->run()の呼出し回数）のペースがほぼ変わらないことを確かめる
	// （design.md 16.1「CPU速度倍率の仕様」）。効果は1回のdrive()内で
	// 処理されるゲスト側CPU命令数に出るため、frames_runでは測れず、
	// ここでは「呼出し間隔（＝VSYNCと音声の生成ペース）が変わらない」
	// ことだけを回帰検知の対象にする。
	{
		bfm_stats before{};
		check(bfm_get_stats(session, &before) == BFM_OK, "計測前の統計を取得できる");
		std::this_thread::sleep_for(std::chrono::milliseconds(200));
		bfm_stats after_x1{};
		check(bfm_get_stats(session, &after_x1) == BFM_OK, "x1の統計を取得できる");
		const uint64_t frames_at_x1 = after_x1.frames_run - before.frames_run;

		command = bfm_command{};
		command.kind = BFM_CMD_SET_SPEED_MULTIPLIER;
		command.arg0 = 4; // x16
		check(bfm_send_command(session, &command, &id) == BFM_OK, "計測用にx16を投入できる");
		check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");

		bfm_stats before_x16{};
		check(bfm_get_stats(session, &before_x16) == BFM_OK, "x16計測前の統計を取得できる");
		std::this_thread::sleep_for(std::chrono::milliseconds(200));
		bfm_stats after_x16{};
		check(bfm_get_stats(session, &after_x16) == BFM_OK, "x16の統計を取得できる");
		const uint64_t frames_at_x16 = after_x16.frames_run - before_x16.frames_run;

		// どちらもおよそ200ms分（12フレーム前後、59.94fps）で、大きな
		// 桁違いにはならないはずである。スレッドpacingのばらつきを
		// 許容しつつ、frames_runがspeed_shift方式のように何倍にも
		// ならないことだけを確認する。
		check(frames_at_x16 < frames_at_x1 * 3 + 6,
		      "x16でもframes_runのペースはx1からVSYNC分以上には増えない"
		      "（壁時計の呼出し間隔は変わらない）");

		command.arg0 = 0; // 以降の検査へ影響しないようx1へ戻す
		check(bfm_send_command(session, &command, &id) == BFM_OK, "x1へ戻せる");
		check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	}

	// Full Speed（SYS-03の無制限）。arg0は0/1のbool、それ以外はinvalid。
	command = bfm_command{};
	command.kind = BFM_CMD_SET_FULL_SPEED;
	command.arg0 = 2;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "不正値も受理はする");
	code = -1;
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	check(code == BFM_ERR_INVALID_ARGUMENT, "0/1以外はinvalidArgument");

	// Full Speedは壁時計の待機を省くことを、frames_runの実測値で
	// 確かめる（bfm_session::full_speedのコメント、design.md 16.1）。
	// 速度倍率（x16）を設定したままでも、Full Speedを有効にしない限り
	// frames_runのペースは壁時計どおりのままのはずである。
	{
		command.arg0 = 4; // x16のまま比較用の基準を取る
		command.kind = BFM_CMD_SET_SPEED_MULTIPLIER;
		check(bfm_send_command(session, &command, &id) == BFM_OK, "計測用にx16を投入できる");
		check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");

		bfm_stats before_x16{};
		check(bfm_get_stats(session, &before_x16) == BFM_OK, "x16計測前の統計を取得できる");
		std::this_thread::sleep_for(std::chrono::milliseconds(100));
		bfm_stats after_x16{};
		check(bfm_get_stats(session, &after_x16) == BFM_OK, "x16の統計を取得できる");
		const uint64_t frames_at_x16 = after_x16.frames_run - before_x16.frames_run;

		command = bfm_command{};
		command.kind = BFM_CMD_SET_FULL_SPEED;
		command.arg0 = 1;
		check(bfm_send_command(session, &command, &id) == BFM_OK, "Full Speedを有効化できる");
		code = -1;
		check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
		check(code == BFM_OK, "Full Speedの有効化が成功で完了する");

		bfm_stats before_full{};
		check(bfm_get_stats(session, &before_full) == BFM_OK, "Full Speed計測前の統計を取得できる");
		std::this_thread::sleep_for(std::chrono::milliseconds(100));
		bfm_stats after_full{};
		check(bfm_get_stats(session, &after_full) == BFM_OK, "Full Speedの統計を取得できる");
		const uint64_t frames_at_full = after_full.frames_run - before_full.frames_run;

		check(frames_at_full > frames_at_x16 * 2,
		      "Full Speedはx16よりさらにframes_runが明確に多い（壁時計の待機がない）");

		command = bfm_command{};
		command.kind = BFM_CMD_SET_FULL_SPEED;
		command.arg0 = 0;
		check(bfm_send_command(session, &command, &id) == BFM_OK, "Full Speedを無効化できる");
		check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");

		command.kind = BFM_CMD_SET_SPEED_MULTIPLIER;
		command.arg0 = 0; // 以降の検査へ影響しないようx1へ戻す
		check(bfm_send_command(session, &command, &id) == BFM_OK, "x1へ戻せる");
		check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	}

	// CPU種別（SYS-05）。
	command = bfm_command{};
	command.kind = BFM_CMD_SET_CPU_TYPE;
	command.arg0 = BFM_CPU_SLOW;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "1.2MHzを投入できる");
	code = -1;
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	check(code == BFM_OK, "既知のCPU種別が成功で完了する");

	command.arg0 = 42;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "不正値も受理はする");
	code = -1;
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	check(code == BFM_ERR_INVALID_ARGUMENT, "不正なCPU種別はinvalidArgument");

	command.arg0 = BFM_CPU_FAST;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "2.0MHzへ戻せる");
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");

	// オプションスイッチ（SYS-06）。
	command = bfm_command{};
	command.kind = BFM_CMD_SET_OPTION_SWITCH;
	command.arg0 = BFM_OPTSW_CYCLE_STEAL | BFM_OPTSW_EXTENDED_RAM | BFM_OPTSW_SYNC_TO_HSYNC;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "3ビットとも投入できる");
	code = -1;
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	check(code == BFM_OK, "既知のビットだけなら成功で完了する");

	command.arg0 = 0;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "全解除も投入できる");
	code = -1;
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	check(code == BFM_OK, "全解除も成功で完了する");

	command.arg0 = 0x8;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "未知ビットも受理はする");
	code = -1;
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	check(code == BFM_ERR_INVALID_ARGUMENT, "未知のビットが立っているとinvalidArgument");

	bfm_stop(session);
	bfm_destroy(session);
}

void test_sound_volume()
{
	group("標準音声チャンネルの音量（AUD-03）");

	bfm_session* session = make_session();
	if (session == nullptr) {
		check(false, "生成できる");
		return;
	}

	bfm_command command{};
	command.kind = BFM_CMD_SET_SOUND_VOLUME;
	command.arg0 = BFM_SOUND_CHANNEL_BEEP;
	command.arg1 = 0;
	check(bfm_send_command(session, &command, nullptr) == BFM_ERR_INVALID_STATE,
	      "未起動では invalidState");

	bfm_start(session);
	check(wait_for_state(session, BFM_STATE_RUNNING, 5000), "running へ遷移する");

	uint64_t id = 0;
	int32_t code = -1;

	// 5チャンネルそれぞれ、最大(0)・中間(-96)・実質無音(-192)が成功する。
	const int64_t channels[] = {
	    BFM_SOUND_CHANNEL_OPN_FM,
	    BFM_SOUND_CHANNEL_OPN_PSG,
	    BFM_SOUND_CHANNEL_BEEP,
	    BFM_SOUND_CHANNEL_KEYBOARD_BEEP,
	    BFM_SOUND_CHANNEL_FDD_MECHANISM,
	};
	for (int64_t channel : channels) {
		for (int64_t decibel : {0, -96, -192}) {
			command = bfm_command{};
			command.kind = BFM_CMD_SET_SOUND_VOLUME;
			command.arg0 = channel;
			command.arg1 = decibel;
			check(bfm_send_command(session, &command, &id) == BFM_OK,
			      "投入できる");
			code = -1;
			check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
			check(code == BFM_OK, "有効なチャンネル・デシベルは成功で完了する");
		}
	}

	// チャンネル番号の範囲外。
	command = bfm_command{};
	command.kind = BFM_CMD_SET_SOUND_VOLUME;
	command.arg0 = -1;
	command.arg1 = 0;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "不正値も受理はする");
	code = -1;
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	check(code == BFM_ERR_INVALID_ARGUMENT, "負のチャンネル番号はinvalidArgument");

	command.arg0 = 5;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "不正値も受理はする");
	code = -1;
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	check(code == BFM_ERR_INVALID_ARGUMENT, "範囲外のチャンネル番号はinvalidArgument");

	// デシベルの範囲外。
	command.arg0 = BFM_SOUND_CHANNEL_BEEP;
	command.arg1 = 1;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "不正値も受理はする");
	code = -1;
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	check(code == BFM_ERR_INVALID_ARGUMENT, "0より大きいデシベルはinvalidArgument");

	command.arg1 = -193;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "不正値も受理はする");
	code = -1;
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	check(code == BFM_ERR_INVALID_ARGUMENT, "-192未満のデシベルはinvalidArgument");

	bfm_stop(session);
	bfm_destroy(session);
}

// --- 別プロセスで行う検査 ---
//
// home_dir はプロセス全体で1つに固定されるため、書込み不能な home_dir を
// 最初の bfm_create で渡す必要がある。
void test_unwritable_home()
{
	group("書込み不能な home_dir");

	// 通常ファイルの配下はディレクトリにできないため、必ず書込みに失敗する。
	// root権限でも結果が変わらず、CIで再現できる。
	bfm_session* session = make_session();
	check(session != nullptr, "生成自体は成功する（失敗はCore threadで判明する）");
	if (session == nullptr) {
		return;
	}

	check(bfm_start(session) == BFM_OK, "起動要求は受理される");
	check(wait_for_state(session, BFM_STATE_FAILED, 5000), "failed へ遷移する");

	bool saw_error = false;
	bfm_event event{};
	while (bfm_poll_event(session, &event) == BFM_OK) {
		if (event.kind == BFM_EVENT_ERROR && event.code == BFM_ERR_CORE_FAILED) {
			saw_error = true;
		}
	}
	check(saw_error, "coreFailed のエラーイベントを通知する");

	bfm_destroy(session);
	check(true, "failed 状態から破棄できる");
}

void test_home_dir_is_process_wide()
{
	group("home_dir はプロセス全体で1つ");

	bfm_session* first = make_session();
	check(first != nullptr, "1つ目を生成できる");
	bfm_destroy(first);

	bfm_session* other = make_session((g_home + "/other").c_str());
	check(other == nullptr, "違う home_dir は invalidState で拒否する");
}

} // namespace

// --- 12. 映像 ---
void test_video()
{
	group("映像");

	bfm_session* session = make_session();
	if (session == nullptr) {
		check(false, "生成できる");
		return;
	}

	bfm_video_frame frame{};
	check(bfm_acquire_video_frame(session, &frame) == BFM_ERR_NO_EVENT,
	      "起動前は取り出せる面がない");
	check(bfm_acquire_video_frame(nullptr, &frame) == BFM_ERR_INVALID_ARGUMENT,
	      "sessionがnullなら invalidArgument");
	check(bfm_acquire_video_frame(session, nullptr) == BFM_ERR_INVALID_ARGUMENT,
	      "outがnullなら invalidArgument");
	bfm_release_video_frame(nullptr, 1); // 落ちないこと
	bfm_release_video_frame(session, 0); // 未知の世代も落ちないこと

	bfm_start(session);
	check(wait_for_state(session, BFM_STATE_RUNNING, 5000), "running へ遷移する");
	check(wait_for_frames_beyond(session, 0, 5000), "フレームが進む");

	// ROMがなくても、起動直後の1枚は無条件に出す。
	// 出さないと、コアが画面へ触るまで真っ黒のままになる。
	bool got = false;
	for (int i = 0; i < 200 && !got; ++i) {
		got = bfm_acquire_video_frame(session, &frame) == BFM_OK;
		if (!got) {
			std::this_thread::sleep_for(std::chrono::milliseconds(10));
		}
	}
	check(got, "起動直後に1枚は公開される");
	if (!got) {
		bfm_stop(session);
		bfm_destroy(session);
		return;
	}

	check(frame.pixels != nullptr, "画素の領域がある");
	check(frame.width == 640 || frame.width == 320, "幅がコアの論理解像度である");
	check(frame.height == 400 || frame.height == 200, "高さがコアの論理解像度である");
	check(frame.generation > 0, "世代が振られている");

	// コアはアルファを書かない。埋めていないと画面全体が背景と混ざる。
	bool alpha_filled = true;
	const size_t count = static_cast<size_t>(frame.width) * frame.height;
	for (size_t i = 0; i < count; ++i) {
		if ((frame.pixels[i] & 0xff000000u) != 0xff000000u) {
			alpha_filled = false;
			break;
		}
	}
	check(alpha_filled, "全画素のアルファが0xffで埋まっている");

	// 借りているあいだは書き潰されない。
	const uint32_t first = frame.pixels[0];
	const uint64_t borrowed = frame.generation;
	std::this_thread::sleep_for(std::chrono::milliseconds(200));
	check(frame.pixels[0] == first, "借りているあいだ内容が変わらない");
	bfm_release_video_frame(session, borrowed);

	// VID-07 画面が変わらない期間は転送しない。
	bfm_stats before{};
	bfm_get_stats(session, &before);
	const uint64_t frames_before = before.frames_run;
	std::this_thread::sleep_for(std::chrono::milliseconds(500));
	bfm_stats after{};
	bfm_get_stats(session, &after);
	check(after.frames_run > frames_before, "コアはフレームを進めている");
	check(after.frames_published < after.frames_run,
	      "VID-07 全フレームを転送してはいない");
	check(after.frames_dropped == 0, "面が尽きて捨てたフレームがない");
	check(after.vm_access_violations == 0, "VM操作はCore threadに閉じている");

	bfm_stop(session);
	bfm_destroy(session);
}

// --- 13. 入力 ---
void test_input()
{
	group("入力");

	bfm_session* session = make_session();
	if (session == nullptr) {
		check(false, "生成できる");
		return;
	}
	bfm_start(session);
	check(wait_for_state(session, BFM_STATE_RUNNING, 5000), "running へ遷移する");

	bfm_command command{};
	command.kind = BFM_CMD_KEY_DOWN;
	command.arg0 = 0x41; // win32 VK_A
	uint64_t id = 0;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "キー押下を投入できる");
	int32_t code = -1;
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	check(code == BFM_OK, "押下が成功で完了する");

	command.kind = BFM_CMD_KEY_UP;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "キー解放を投入できる");
	code = -1;
	check(wait_for_completion(session, id, 5000, &code), "完了通知が届く");
	check(code == BFM_OK, "解放が成功で完了する");

	command.kind = BFM_CMD_KEY_DOWN;
	command.arg0 = -1;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "範囲外も受理はする");
	code = -1;
	check(wait_for_completion(session, id, 5000, &code), "範囲外の完了通知が届く");
	check(code == BFM_ERR_INVALID_ARGUMENT, "負のキーコードは invalidArgument で完了");

	command.arg0 = 0x100;
	check(bfm_send_command(session, &command, &id) == BFM_OK, "上限超えも受理はする");
	code = -1;
	check(wait_for_completion(session, id, 5000, &code), "上限超えの完了通知が届く");
	check(code == BFM_ERR_INVALID_ARGUMENT, "0xffを超えるキーコードは invalidArgument で完了");

	bfm_stop(session);
	bfm_destroy(session);
}

// --- 14. 音声 ---
void test_audio()
{
	group("音声");

	bfm_session* session = make_session();
	if (session == nullptr) {
		check(false, "生成できる");
		return;
	}

	uint32_t sample_rate = 0;
	uint32_t channels = 0;
	check(bfm_get_audio_format(session, &sample_rate, &channels) == BFM_OK,
	      "フォーマットを取得できる");
	check(sample_rate == 48000, "サンプルレートは48kHz固定（design.md 7）");
	check(channels == 2, "ステレオ固定");
	check(bfm_get_audio_format(nullptr, &sample_rate, &channels) == BFM_ERR_INVALID_ARGUMENT,
	      "sessionがnullなら invalidArgument");
	check(bfm_get_audio_format(session, nullptr, &channels) == BFM_ERR_INVALID_ARGUMENT,
	      "out_sample_rateがnullなら invalidArgument");

	check(bfm_read_audio(nullptr, nullptr, 0) == BFM_ERR_INVALID_ARGUMENT,
	      "sessionがnullなら invalidArgument");

	std::vector<int16_t> silent(200 * 2, 0x1234);
	check(bfm_read_audio(session, silent.data(), 100) == BFM_OK,
	      "起動前でも読める（無音で埋まる）");
	bool all_silent = true;
	for (size_t i = 0; i < 100 * 2; ++i) {
		if (silent[i] != 0) {
			all_silent = false;
		}
	}
	check(all_silent, "起動前の読み出しは無音");

	bfm_start(session);
	check(wait_for_state(session, BFM_STATE_RUNNING, 5000), "running へ遷移する");

	// 生産と消費をだいたい同じ速さで回し、有界リングが尽きて
	// 極端なオーバーランにならないようにする（design.md 7）。
	std::vector<int16_t> buffer(4800 * 2, 0);
	for (int i = 0; i < 20; ++i) {
		bfm_read_audio(session, buffer.data(), 800);
		std::this_thread::sleep_for(std::chrono::milliseconds(20));
	}

	bfm_stats stats{};
	check(bfm_get_stats(session, &stats) == BFM_OK, "統計を取得できる");
	check(stats.audio_frames_produced > 0, "コアがPCMを生成している");
	check(stats.vm_access_violations == 0, "VM操作はCore threadに閉じている");
	std::printf("   生成 %llu フレーム / アンダーラン %llu / オーバーラン %llu\n",
	            static_cast<unsigned long long>(stats.audio_frames_produced),
	            static_cast<unsigned long long>(stats.audio_underrun_frames),
	            static_cast<unsigned long long>(stats.audio_overrun_frames));

	bfm_stop(session);

	// 停止後も安全に読める（無音で埋まる。emu/osdの寿命に依存しない）。
	check(bfm_read_audio(session, buffer.data(), 4800) == BFM_OK, "停止後も読める");

	bfm_destroy(session);
}

// --- 14. FDD媒体（WP5） ---
//
// C ABIの挿入・排出・アクセス状態の配線を検査する。書き戻しの原子性
// （CacheWorkspace経由のrename）はDart側の責務であり、design.md 16.1に
// 記録する。ここではコアが受理・排出したことと、イベント／エラーコードが
// design.md 9.1のとおり届くことだけを確かめる。
void test_media()
{
	group("FDD媒体");

	const std::string media_dir = g_home + "/media-test";
	mkdir(media_dir.c_str(), 0700);
	const std::string fd1_image = media_dir + "/fd1.d88";
	const std::string fd2_image = media_dir + "/fd2.d88";
	check(write_blank_d88(fd1_image), "FD1用のテストイメージを作れる");
	check(write_blank_d88(fd2_image), "FD2用のテストイメージを作れる");

	bfm_session* session = make_session();
	if (session == nullptr) {
		check(false, "生成できる");
		return;
	}
	bfm_start(session);
	check(wait_for_state(session, BFM_STATE_RUNNING, 5000), "running へ遷移する");

	// id 完了までのあいだに届いた全イベントを集め、呼び手が両方（挿入通知と
	// 完了通知）を検査できるようにする。wait_for_completion() はcommand_id
	// 一致以外のイベントを読み捨てるため、ここでは使わない。
	auto send_and_collect = [&](const bfm_command& command, std::vector<bfm_event>* out) -> int32_t {
		uint64_t id = 0;
		if (bfm_send_command(session, &command, &id) != BFM_OK) {
			return -1;
		}
		for (int i = 0; i < 5000; ++i) {
			bfm_event event{};
			while (bfm_poll_event(session, &event) == BFM_OK) {
				out->push_back(event);
				if (event.kind == BFM_EVENT_COMMAND_COMPLETED && event.command_id == id) {
					return event.code;
				}
			}
			std::this_thread::sleep_for(std::chrono::milliseconds(1));
		}
		return -1;
	};

	auto has_media_changed = [](const std::vector<bfm_event>& events, int64_t drv,
	                            int64_t inserted) {
		for (const auto& event : events) {
			if (event.kind == BFM_EVENT_MEDIA_CHANGED && event.arg0 == drv &&
			    event.arg1 == inserted) {
				return true;
			}
		}
		return false;
	};

	// FD1へ挿入する。
	bfm_command insert_fd1{};
	insert_fd1.kind = BFM_CMD_INSERT_FDD;
	insert_fd1.arg0 = 0; // FD1
	insert_fd1.arg1 = 0; // bank 0
	insert_fd1.text = fd1_image.c_str();
	std::vector<bfm_event> events;
	check(send_and_collect(insert_fd1, &events) == BFM_OK, "FD1への挿入が成功で完了する");
	check(has_media_changed(events, 0, 1), "FD1挿入のMEDIA_CHANGEDが届く");

	// 挿入済みドライブへの再挿入は拒否する（先に排出させる）。
	events.clear();
	check(send_and_collect(insert_fd1, &events) == BFM_ERR_INVALID_STATE,
	      "挿入済みドライブへの再挿入は invalidState");

	// FD2は独立して挿入できる。
	bfm_command insert_fd2{};
	insert_fd2.kind = BFM_CMD_INSERT_FDD;
	insert_fd2.arg0 = 1; // FD2
	insert_fd2.arg1 = 0;
	insert_fd2.text = fd2_image.c_str();
	events.clear();
	check(send_and_collect(insert_fd2, &events) == BFM_OK, "FD2への挿入が成功で完了する");
	check(has_media_changed(events, 1, 1), "FD2挿入のMEDIA_CHANGEDが届く");

	// 範囲外のドライブは invalidArgument。
	bfm_command insert_out_of_range = insert_fd1;
	insert_out_of_range.arg0 = 2;
	events.clear();
	check(send_and_collect(insert_out_of_range, &events) == BFM_ERR_INVALID_ARGUMENT,
	      "範囲外のドライブは invalidArgument");

	// 負のバンクは invalidArgument。
	bfm_command insert_bad_bank = insert_fd1;
	insert_bad_bank.arg0 = 0;
	insert_bad_bank.arg1 = -1;
	events.clear();
	check(send_and_collect(insert_bad_bank, &events) == BFM_ERR_INVALID_ARGUMENT,
	      "負のバンクは invalidArgument（挿入済みのため invalidState 以前に弾く必要はない）");

	// 存在しないパスはコアが受理せず invalidArgument で完了する。
	bfm_command eject_fd1{};
	eject_fd1.kind = BFM_CMD_EJECT_FDD;
	eject_fd1.arg0 = 0;
	events.clear();
	check(send_and_collect(eject_fd1, &events) == BFM_OK, "FD1の排出が成功で完了する");
	check(has_media_changed(events, 0, 0), "FD1排出のMEDIA_CHANGEDが届く");

	const std::string missing_image = media_dir + "/does-not-exist.d88";
	bfm_command insert_missing{};
	insert_missing.kind = BFM_CMD_INSERT_FDD;
	insert_missing.arg0 = 0;
	insert_missing.arg1 = 0;
	insert_missing.text = missing_image.c_str();
	events.clear();
	check(send_and_collect(insert_missing, &events) == BFM_ERR_INVALID_ARGUMENT,
	      "存在しないパスは invalidArgument（コアが受理しない）");
	check(!has_media_changed(events, 0, 1), "受理されなければMEDIA_CHANGEDは届かない");

	// 排出済みドライブへの再挿入は成功する（ドライブが解放されている）。
	events.clear();
	check(send_and_collect(insert_fd1, &events) == BFM_OK, "排出後の再挿入は成功する");
	check(has_media_changed(events, 0, 1), "再挿入のMEDIA_CHANGEDが届く");

	// 未挿入ドライブへの排出は冪等にOKとし、通知は出さない。
	bfm_command eject_fd2{};
	eject_fd2.kind = BFM_CMD_EJECT_FDD;
	eject_fd2.arg0 = 1;
	events.clear();
	check(send_and_collect(eject_fd2, &events) == BFM_OK, "FD2の排出が成功で完了する");
	events.clear();
	check(send_and_collect(eject_fd2, &events) == BFM_OK, "未挿入ドライブへの排出も冪等にOK");
	check(!has_media_changed(events, 1, 0), "未挿入からの排出はMEDIA_CHANGEDを出さない");

	// 範囲外のドライブへの排出も invalidArgument。
	bfm_command eject_out_of_range{};
	eject_out_of_range.kind = BFM_CMD_EJECT_FDD;
	eject_out_of_range.arg0 = 2;
	events.clear();
	check(send_and_collect(eject_out_of_range, &events) == BFM_ERR_INVALID_ARGUMENT,
	      "範囲外のドライブへの排出は invalidArgument");

	// --- M3 FDD-06: 書込み保護・タイミング補正・CRCエラー無視 ---
	bfm_command write_protect{};
	write_protect.kind = BFM_CMD_SET_FDD_WRITE_PROTECT;
	write_protect.arg0 = 0;
	write_protect.arg1 = 1;
	events.clear();
	check(send_and_collect(write_protect, &events) == BFM_OK, "FD1の書込み保護を設定できる");

	bfm_command timing{};
	timing.kind = BFM_CMD_SET_FDD_TIMING;
	timing.arg0 = 0;
	timing.arg1 = 1;
	events.clear();
	check(send_and_collect(timing, &events) == BFM_OK, "FD1のタイミング補正を設定できる");

	bfm_command crc{};
	crc.kind = BFM_CMD_SET_FDD_CRC_CHECK;
	crc.arg0 = 0;
	crc.arg1 = 1;
	events.clear();
	check(send_and_collect(crc, &events) == BFM_OK, "FD1のCRCエラー無視を設定できる");

	bfm_command bad_drive_switch = write_protect;
	bad_drive_switch.arg0 = 2;
	events.clear();
	check(send_and_collect(bad_drive_switch, &events) == BFM_ERR_INVALID_ARGUMENT,
	      "範囲外のドライブへの書込み保護設定は invalidArgument");

	bfm_command bad_value_switch = write_protect;
	bad_value_switch.arg1 = 2;
	events.clear();
	check(send_and_collect(bad_value_switch, &events) == BFM_ERR_INVALID_ARGUMENT,
	      "0/1以外の値は invalidArgument");

	// ここまででFD1は挿入済み（「排出後の再挿入は成功する」）。以降の
	// テストは空きドライブを前提とするため、先に排出しておく。
	events.clear();
	check(send_and_collect(eject_fd1, &events) == BFM_OK, "後続検査のためFD1を排出できる");

	// --- M3 FDD-03: rawイメージのサイズ検証 ---
	const std::string bad_raw_image = media_dir + "/bad.raw";
	check(write_file(bad_raw_image, std::string(1234, '\0')),
	      "不正サイズのrawテストイメージを作れる");
	bfm_command insert_bad_raw{};
	insert_bad_raw.kind = BFM_CMD_INSERT_FDD;
	insert_bad_raw.arg0 = 0;
	insert_bad_raw.arg1 = 0;
	insert_bad_raw.text = bad_raw_image.c_str();
	events.clear();
	check(send_and_collect(insert_bad_raw, &events) == BFM_ERR_UNSUPPORTED_GEOMETRY,
	      "2D/2DDのバイト数と一致しないrawは unsupportedGeometry");
	check(!has_media_changed(events, 0, 1), "拒否されればMEDIA_CHANGEDは届かない");

	// --- M3 FDD-05: 空の2D/2DDディスク作成 ---
	const std::string blank_2d = media_dir + "/blank-2d.d88";
	bfm_command create_blank_2d{};
	create_blank_2d.kind = BFM_CMD_CREATE_BLANK_FDD;
	create_blank_2d.arg0 = BFM_FDD_MEDIA_2D;
	create_blank_2d.text = blank_2d.c_str();
	events.clear();
	check(send_and_collect(create_blank_2d, &events) == BFM_OK, "空の2Dディスクを作成できる");
	check(is_regular_file(blank_2d), "作成先に実ファイルが残る");

	const std::string blank_2dd = media_dir + "/blank-2dd.d88";
	bfm_command create_blank_2dd{};
	create_blank_2dd.kind = BFM_CMD_CREATE_BLANK_FDD;
	create_blank_2dd.arg0 = BFM_FDD_MEDIA_2DD;
	create_blank_2dd.text = blank_2dd.c_str();
	events.clear();
	check(send_and_collect(create_blank_2dd, &events) == BFM_OK, "空の2DDディスクを作成できる");

	bfm_command create_blank_bad_type = create_blank_2d;
	create_blank_bad_type.arg0 = 99;
	events.clear();
	check(send_and_collect(create_blank_bad_type, &events) == BFM_ERR_INVALID_ARGUMENT,
	      "不正な媒体種別は invalidArgument");

	// 作成した空ディスクをFD1へ挿入できる（バンク情報も検査する）。
	bfm_command insert_blank = insert_fd1;
	insert_blank.text = blank_2d.c_str();
	events.clear();
	check(send_and_collect(insert_blank, &events) == BFM_OK, "作成した空の2Dディスクを挿入できる");

	// --- M3 FDD-04: バンク情報の取得 ---
	int32_t bank_num = -1;
	int32_t cur_bank = -1;
	check(bfm_get_fdd_bank_info(session, 0, &bank_num, &cur_bank) == BFM_OK,
	      "バンク情報を取得できる");
	check(bank_num == 1, "単一バンクのD88はbank_num==1");
	check(cur_bank == 0, "単一バンクのD88はcur_bank==0");

	check(bfm_get_fdd_bank_info(session, 2, &bank_num, &cur_bank) == BFM_ERR_INVALID_ARGUMENT,
	      "範囲外のドライブは invalidArgument");

	events.clear();
	check(send_and_collect(eject_fd1, &events) == BFM_OK, "挿入済みのFD1を排出できる");
	check(bfm_get_fdd_bank_info(session, 0, &bank_num, &cur_bank) == BFM_OK,
	      "排出後もバンク情報を取得できる");
	check(bank_num == 0, "排出後はbank_num==0");

	// --- M3 FDD-06: 書込み保護の実際値はマウント中のディスクに従う ---
	//
	// vm/disk.cppのDISK::open()は呼出しのたびにwrite_protectedをまず
	// falseへ戻し、開いたファイル自身のヘッダprotectバイトを見て必要なら
	// trueへ立て直す。DISK::close()は変更があれば現在のwrite_protected
	// をそのファイル自身のヘッダへ書き戻すため、書込み保護は「ドライブの
	// 記憶」ではなく「そのファイル自身が持つ状態」である（利用者からの
	// 指摘の再現検査）。ここでは2つの別ファイルを使い、一方を保護しても
	// もう一方へ持ち越されないことを確かめる。
	const std::string protected_image = media_dir + "/protected.d88";
	check(write_blank_d88(protected_image, /*protect=*/true),
	      "書込み保護済みのテストイメージを作れる");
	const std::string unprotected_image = media_dir + "/unprotected.d88";
	check(write_blank_d88(unprotected_image, /*protect=*/false),
	      "書込み保護なしのテストイメージを作れる");

	bfm_command insert_protected = insert_fd1;
	insert_protected.text = protected_image.c_str();
	events.clear();
	check(send_and_collect(insert_protected, &events) == BFM_OK,
	      "書込み保護済みディスクを挿入できる");
	int32_t write_protected = -1;
	check(bfm_get_fdd_write_protect(session, 0, &write_protected) == BFM_OK,
	      "書込み保護の実際値を取得できる");
	check(write_protected == 1, "保護済みディスクのヘッダを反映してtrueになる");

	events.clear();
	check(send_and_collect(eject_fd1, &events) == BFM_OK, "保護済みディスクを排出できる");
	bfm_command insert_unprotected = insert_fd1;
	insert_unprotected.text = unprotected_image.c_str();
	events.clear();
	check(send_and_collect(insert_unprotected, &events) == BFM_OK,
	      "書込み保護されていない別ディスクを同じドライブへ挿入できる");
	write_protected = -1;
	check(bfm_get_fdd_write_protect(session, 0, &write_protected) == BFM_OK &&
	          write_protected == 0,
	      "前のディスクの保護状態を持ち越さず、新しいディスクのヘッダに従う");

	events.clear();
	check(send_and_collect(write_protect, &events) == BFM_OK,
	      "マウント中のディスクへ明示的に保護を設定できる");
	write_protected = -1;
	check(bfm_get_fdd_write_protect(session, 0, &write_protected) == BFM_OK &&
	          write_protected == 1,
	      "明示設定した値が実際値として読める");

	check(bfm_get_fdd_write_protect(session, 2, &write_protected) ==
	          BFM_ERR_INVALID_ARGUMENT,
	      "範囲外のドライブは invalidArgument");

	events.clear();
	check(send_and_collect(eject_fd1, &events) == BFM_OK, "後続検査のためFD1を排出できる");
	write_protected = -1;
	check(bfm_get_fdd_write_protect(session, 0, &write_protected) == BFM_OK &&
	          write_protected == 0,
	      "排出後は書込み保護もfalseへ戻る");

	bfm_stats stats{};
	check(bfm_get_stats(session, &stats) == BFM_OK, "統計を取得できる");
	check(stats.vm_access_violations == 0, "VM操作はCore threadに閉じている");

	// --- M3 STA-01/STA-02: 状態保存・読込み ---
	//
	// コアのEMU::save_state/load_stateはvoidを返し、非互換/破損時は内部で
	// 現在の実行状態へ自動ロールバックする（design.md「状態保存（M3、
	// STA-01/STA-02）の実装方式」）。ブリッジはロード前に先頭4バイト
	// （コアのSTATE_VERSION）だけを事前チェックして拒否する。ここでは
	// (1)保存直後のファイル先頭4バイトがブリッジの既知値と一致すること
	// （rot検知）、(2)保存→ロードでFD1挿入状態が正しく復元され
	// MEDIA_CHANGEDが飛ぶこと、(3)壊れたヘッダはBFM_ERR_STATE_INCOMPATIBLE
	// で拒否されることを検査する。
	{
		auto read_u32_le_header = [](const std::string& path) -> int64_t {
			FILE* f = fopen(path.c_str(), "rb");
			if (f == nullptr) {
				return -1;
			}
			uint8_t header[4] = {0, 0, 0, 0};
			const size_t n = fread(header, 1, sizeof(header), f);
			fclose(f);
			if (n != sizeof(header)) {
				return -1;
			}
			return static_cast<int64_t>(header[0]) | (static_cast<int64_t>(header[1]) << 8) |
			       (static_cast<int64_t>(header[2]) << 16) | (static_cast<int64_t>(header[3]) << 24);
		};

		const std::string state_dir = g_home + "/state-test";
		mkdir(state_dir.c_str(), 0700);
		const std::string state_with_disk = state_dir + "/slot-with-disk.bin";
		const std::string state_empty = state_dir + "/slot-empty.bin";
		const std::string state_corrupt = state_dir + "/slot-corrupt.bin";

		// FD1に何も挿入していない状態を保存する。
		bfm_command save_empty{};
		save_empty.kind = BFM_CMD_SAVE_STATE;
		save_empty.text = state_empty.c_str();
		events.clear();
		check(send_and_collect(save_empty, &events) == BFM_OK, "未挿入状態を保存できる");
		check(is_regular_file(state_empty), "保存先に実ファイルが残る");
		check(read_u32_le_header(state_empty) == 3,
		      "保存直後のファイル先頭4バイトがブリッジの既知STATE_VERSIONと一致する"
		      "（emu.cppの#defineが変わっていたらここで気づく）");

		// FD1へディスクを挿入してから保存する。
		events.clear();
		check(send_and_collect(insert_fd1, &events) == BFM_OK, "状態保存検査用にFD1へ挿入できる");
		bfm_command save_with_disk{};
		save_with_disk.kind = BFM_CMD_SAVE_STATE;
		save_with_disk.text = state_with_disk.c_str();
		events.clear();
		check(send_and_collect(save_with_disk, &events) == BFM_OK, "FD1挿入状態を保存できる");

		check(send_and_collect(eject_fd1, &events) == BFM_OK, "後続検査のためFD1を排出できる");

		// 未挿入状態へロードし直す（差分なし、MEDIA_CHANGEDは飛ばない）。
		bfm_command load_empty{};
		load_empty.kind = BFM_CMD_LOAD_STATE;
		load_empty.text = state_empty.c_str();
		events.clear();
		check(send_and_collect(load_empty, &events) == BFM_OK, "未挿入状態を読み込める");

		// FD1挿入状態へロードし直す（差分あり、MEDIA_CHANGEDが飛ぶ）。
		bfm_command load_with_disk{};
		load_with_disk.kind = BFM_CMD_LOAD_STATE;
		load_with_disk.text = state_with_disk.c_str();
		events.clear();
		check(send_and_collect(load_with_disk, &events) == BFM_OK, "FD1挿入状態を読み込める");
		bool saw_media_changed = false;
		for (const auto& event : events) {
			if (event.kind == BFM_EVENT_MEDIA_CHANGED && event.arg0 == 0 && event.arg1 == 1) {
				saw_media_changed = true;
			}
		}
		check(saw_media_changed,
		      "ロードでFD1挿入状態が変わるとMEDIA_CHANGEDが飛ぶ（ポーリングされない"
		      "イベントのためロード側で明示発行する必要がある）");
		int32_t bank_num = -1;
		int32_t cur_bank = -1;
		check(bfm_get_fdd_bank_info(session, 0, &bank_num, &cur_bank) == BFM_OK && bank_num == 1,
		      "ロード後、復元されたFD1のバンク情報を読める");

		// 壊れた（先頭バージョンが不一致な）ファイルは拒否され、
		// 現在のセッション（FD1挿入中のまま）を壊さない。
		std::vector<uint8_t> corrupt_bytes;
		{
			FILE* src = fopen(state_with_disk.c_str(), "rb");
			check(src != nullptr, "壊すための元ファイルを開ける");
			fseek(src, 0, SEEK_END);
			const long size = ftell(src);
			fseek(src, 0, SEEK_SET);
			corrupt_bytes.resize(static_cast<size_t>(size));
			check(fread(corrupt_bytes.data(), 1, corrupt_bytes.size(), src) == corrupt_bytes.size(),
			      "元ファイルを読める");
			fclose(src);
		}
		check(corrupt_bytes.size() >= 4, "先頭4バイトを壊せる長さがある");
		corrupt_bytes[0] = static_cast<uint8_t>(corrupt_bytes[0] ^ 0xFF);
		FILE* dst = fopen(state_corrupt.c_str(), "wb");
		check(dst != nullptr, "壊れたファイルを書ける");
		fwrite(corrupt_bytes.data(), 1, corrupt_bytes.size(), dst);
		fclose(dst);

		bfm_command load_corrupt{};
		load_corrupt.kind = BFM_CMD_LOAD_STATE;
		load_corrupt.text = state_corrupt.c_str();
		events.clear();
		check(send_and_collect(load_corrupt, &events) == BFM_ERR_STATE_INCOMPATIBLE,
		      "先頭バージョン不一致のファイルはstateIncompatibleで拒否される");
		bool saw_media_changed_on_reject = false;
		for (const auto& event : events) {
			if (event.kind == BFM_EVENT_MEDIA_CHANGED) {
				saw_media_changed_on_reject = true;
			}
		}
		check(!saw_media_changed_on_reject, "拒否時はMEDIA_CHANGEDを出さない");
		bank_num = -1;
		cur_bank = -1;
		check(bfm_get_fdd_bank_info(session, 0, &bank_num, &cur_bank) == BFM_OK && bank_num == 1,
		      "拒否後もFD1挿入状態は壊れたロードの影響を受けない");

		const std::string missing_path = state_dir + "/does-not-exist.bin";
		bfm_command load_missing{};
		load_missing.kind = BFM_CMD_LOAD_STATE;
		load_missing.text = missing_path.c_str();
		events.clear();
		check(send_and_collect(load_missing, &events) == BFM_ERR_STATE_INCOMPATIBLE,
		      "存在しないファイルもstateIncompatibleで拒否される");

		bfm_command save_no_path{};
		save_no_path.kind = BFM_CMD_SAVE_STATE;
		events.clear();
		check(send_and_collect(save_no_path, &events) == BFM_ERR_INVALID_ARGUMENT,
		      "パス無しの保存はinvalidArgument");
	}

	bfm_stop(session);
	bfm_destroy(session);
}

int main(int argc, char** argv)
{
	if (argc < 2) {
		std::fprintf(stderr, "usage: %s <home-dir>\n", argv[0]);
		return 2;
	}
	g_home = argv[1];

	// home_dir を固定してしまう検査は別プロセスで行う。
	if (argc >= 3 && std::strcmp(argv[2], "--unwritable-home") == 0) {
		g_home = "/dev/null/bubi-unwritable";
		test_unwritable_home();
		std::printf("\n%s\n", failures == 0 ? "すべて合格" : "失敗あり");
		return failures == 0 ? 0 : 1;
	}

	test_argument_validation();
	test_lifecycle();
	test_repeated_cycles();
	test_command_events();
	test_core_thread_ownership();
	test_initialization_failure();
	test_command_queue_saturation();
	test_ui_stall();
	test_single_live_session();
	test_rom_wiring();
	test_boot_mode();
	test_run_settings();
	test_sound_volume();
	test_video();
	test_input();
	test_audio();
	test_media();
	test_home_dir_is_process_wide();

	std::printf("\n%s\n", failures == 0 ? "すべて合格" : "失敗あり");
	return failures == 0 ? 0 : 1;
}
