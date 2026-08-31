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
#include <chrono>
#include <cstdio>
#include <cstdlib>
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
                          uint32_t event_capacity = 0)
{
	bfm_create_options options{};
	options.home_dir = (home != nullptr) ? home : g_home.c_str();
	options.command_queue_capacity = command_capacity;
	options.event_queue_capacity = event_capacity;

	bfm_session* session = nullptr;
	if (bfm_create(&options, &session) != BFM_OK) {
		return nullptr;
	}
	return session;
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
		std::this_thread::sleep_for(std::chrono::milliseconds(40));
		bfm_stats after{};
		bfm_get_stats(session, &after);
		if (after.frames_run <= stats.frames_run) {
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
void test_initialization_failure()
{
	group("初期化失敗");

	// 通常ファイルの配下はディレクトリにできないため、必ず書込みに失敗する。
	// root権限でも結果が変わらず、CIで再現できる。
	bfm_session* session = make_session("/dev/null/bubi-unwritable");
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

} // namespace

int main(int argc, char** argv)
{
	if (argc < 2) {
		std::fprintf(stderr, "usage: %s <home-dir>\n", argv[0]);
		return 2;
	}
	g_home = argv[1];

	test_argument_validation();
	test_lifecycle();
	test_repeated_cycles();
	test_command_events();
	test_core_thread_ownership();
	test_initialization_failure();
	test_command_queue_saturation();
	test_ui_stall();
	test_single_live_session();

	std::printf("\n%s\n", failures == 0 ? "すべて合格" : "失敗あり");
	return failures == 0 ? 0 : 1;
}
