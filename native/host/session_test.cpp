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

	// 型として定義済みだが未実装のコマンドは unsupported で完了する。
	bfm_command media{};
	media.kind = BFM_CMD_INSERT_FDD;
	media.text = "/dev/null/not-a-real-image";
	uint64_t media_id = 0;
	check(bfm_send_command(session, &media, &media_id) == BFM_OK, "未実装コマンドも受け付ける");
	code = -1;
	check(wait_for_completion(session, media_id, 5000, &code), "未実装コマンドの完了通知が届く");
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
	test_home_dir_is_process_wide();

	std::printf("\n%s\n", failures == 0 ? "すべて合格" : "失敗あり");
	return failures == 0 ? 0 : 1;
}
