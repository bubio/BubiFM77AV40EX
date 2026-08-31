/*
 * 技術検証spikeの検査本体（development_plan.md 5.3）。
 *
 * 合格条件:
 *   C ABI      : 作成・起動・停止を繰り返してリークや境界外例外がない
 *   Core thread: UI停止やキュー飽和でも安全に停止できる
 *
 * リーク検査は本体では行わず、scripts/run_spikes.sh が
 * macOSの leaks(1) で外側から判定する。
 */
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>

#include "bfm_session_spike.h"

namespace {

int failures = 0;

void check(bool condition, const char* what)
{
	std::printf("  [%s] %s\n", condition ? " ok " : "FAIL", what);
	if (!condition) {
		++failures;
	}
}

std::string g_home;

bfm_session* make_session(uint32_t command_capacity = 0, uint32_t event_capacity = 0)
{
	bfm_create_options options{};
	options.home_dir = g_home.c_str();
	options.command_queue_capacity = command_capacity;
	options.event_queue_capacity = event_capacity;

	bfm_session* session = nullptr;
	if (bfm_create(&options, &session) != BFM_OK) {
		return nullptr;
	}
	return session;
}

// 状態が期待値になるまで待つ。最大 timeout_ms。
bool wait_for_state(bfm_session* session, bfm_state expected, int timeout_ms)
{
	for (int i = 0; i < timeout_ms; ++i) {
		if (bfm_get_state(session) == expected) {
			return true;
		}
		std::this_thread::sleep_for(std::chrono::milliseconds(1));
	}
	return false;
}

// --- C ABI: 所有権と引数検証 ---
void test_argument_validation()
{
	std::printf("C ABI: argument validation and ownership\n");

	bfm_session* session = nullptr;
	check(bfm_create(nullptr, &session) == BFM_ERR_INVALID_ARGUMENT,
	      "bfm_create rejects null options");
	check(session == nullptr, "out handle is untouched on failure");

	bfm_create_options options{};
	options.home_dir = nullptr;
	check(bfm_create(&options, &session) == BFM_ERR_INVALID_ARGUMENT,
	      "bfm_create rejects missing home_dir");

	check(bfm_start(nullptr) == BFM_ERR_INVALID_ARGUMENT, "bfm_start rejects null handle");
	check(bfm_stop(nullptr) == BFM_ERR_INVALID_ARGUMENT, "bfm_stop rejects null handle");
	check(bfm_get_state(nullptr) == BFM_STATE_STOPPED, "bfm_get_state tolerates null handle");

	bfm_destroy(nullptr);
	check(true, "bfm_destroy tolerates null handle");

	bfm_event event{};
	session = make_session();
	check(session != nullptr, "bfm_create succeeds with valid options");
	check(bfm_poll_event(session, &event) == BFM_ERR_NO_EVENT,
	      "a session that has never started has no events");
	check(bfm_poll_event(session, nullptr) == BFM_ERR_INVALID_ARGUMENT,
	      "bfm_poll_event rejects null out");
	bfm_destroy(session);
}

// --- C ABI: ライフサイクルと冪等性 ---
void test_lifecycle()
{
	std::printf("C ABI: lifecycle, double start, idempotent stop and destroy\n");

	bfm_session* session = make_session();
	check(bfm_get_state(session) == BFM_STATE_STOPPED, "new session is stopped");

	// 停止中のコマンドは受け付けない。
	check(bfm_reset(session, BFM_RESET_NORMAL, nullptr) == BFM_ERR_INVALID_STATE,
	      "commands are rejected while stopped");

	check(bfm_start(session) == BFM_OK, "start succeeds");
	check(wait_for_state(session, BFM_STATE_RUNNING, 3000), "session reaches running");
	check(bfm_start(session) == BFM_ERR_INVALID_STATE, "double start is rejected");

	check(bfm_stop(session) == BFM_OK, "stop succeeds");
	check(bfm_get_state(session) == BFM_STATE_STOPPED, "session is stopped after stop");
	check(bfm_stop(session) == BFM_OK, "stop is idempotent");

	bfm_destroy(session);
	check(true, "destroy after stop completes");
}

// --- C ABI: 作成・起動・停止の繰り返し ---
void test_repeated_cycles()
{
	std::printf("C ABI: repeated create/start/stop/destroy\n");

	constexpr int kCycles = 20;
	bool all_ok = true;
	bool every_cycle_advanced = true;
	uint64_t total_frames = 0;

	for (int i = 0; i < kCycles; ++i) {
		bfm_session* session = make_session();
		if (session == nullptr) {
			all_ok = false;
			break;
		}
		if (bfm_start(session) != BFM_OK || !wait_for_state(session, BFM_STATE_RUNNING, 3000)) {
			all_ok = false;
			bfm_destroy(session);
			break;
		}
		std::this_thread::sleep_for(std::chrono::milliseconds(20));

		bfm_stats stats{};
		bfm_get_stats(session, &stats);
		if (stats.frames_run == 0) {
			every_cycle_advanced = false;
		}
		total_frames += stats.frames_run;

		bfm_destroy(session);   // stopを内包する
	}

	check(all_ok, "20 cycles of create/start/stop/destroy succeed");
	check(every_cycle_advanced, "the core thread advanced frames in every cycle");
	std::printf("       total frames across cycles: %llu\n",
	            static_cast<unsigned long long>(total_frames));
}

// --- C ABI: コマンドとイベントの対応 ---
void test_command_event_pairing()
{
	std::printf("C ABI: command ids are echoed back as completion events\n");

	bfm_session* session = make_session();
	bfm_start(session);
	wait_for_state(session, BFM_STATE_RUNNING, 3000);

	uint64_t reset_id = 0;
	uint64_t special_id = 0;
	check(bfm_reset(session, BFM_RESET_NORMAL, &reset_id) == BFM_OK, "reset is accepted");
	check(bfm_reset(session, BFM_RESET_SPECIAL, &special_id) == BFM_OK,
	      "special reset is accepted");
	check(reset_id != 0 && special_id == reset_id + 1, "command ids are sequential");

	bool saw_reset = false;
	bool saw_special = false;
	for (int i = 0; i < 3000 && !(saw_reset && saw_special); ++i) {
		bfm_event event{};
		while (bfm_poll_event(session, &event) == BFM_OK) {
			if (event.kind == BFM_EVENT_COMMAND_COMPLETED) {
				if (event.command_id == reset_id) saw_reset = true;
				if (event.command_id == special_id) saw_special = true;
			}
		}
		std::this_thread::sleep_for(std::chrono::milliseconds(1));
	}
	check(saw_reset && saw_special, "both commands report completion with their own id");

	bfm_destroy(session);
}

// --- Core thread: 例外封じ込め ---
void test_exception_containment()
{
	std::printf("Core thread: an exception never crosses the boundary\n");

	bfm_session* session = make_session();
	bfm_start(session);
	wait_for_state(session, BFM_STATE_RUNNING, 3000);

	bfm_command command{};
	command.kind = BFM_CMD_SPIKE_THROW;
	check(bfm_send_command(session, &command, nullptr) == BFM_OK, "throwing command is accepted");

	check(wait_for_state(session, BFM_STATE_FAILED, 3000),
	      "session moves to failed instead of terminating the process");

	bool saw_error = false;
	bfm_event event{};
	while (bfm_poll_event(session, &event) == BFM_OK) {
		if (event.kind == BFM_EVENT_ERROR && event.code == BFM_ERR_CORE_FAILED) {
			saw_error = true;
		}
	}
	check(saw_error, "the failure is reported as an error event");
	check(bfm_stop(session) == BFM_OK, "stop still succeeds after a core failure");

	bfm_destroy(session);
}

// --- Core thread: コマンドキュー飽和 ---
void test_command_queue_saturation()
{
	std::printf("Core thread: bounded command queue rejects instead of growing\n");

	constexpr uint32_t kCapacity = 8;
	bfm_session* session = make_session(kCapacity, 0);
	bfm_start(session);
	wait_for_state(session, BFM_STATE_RUNNING, 3000);

	// Core threadを滞留させ、UI側からコマンドを溢れさせる。
	bfm_command stall{};
	stall.kind = BFM_CMD_SPIKE_STALL;
	stall.arg = 300;
	bfm_send_command(session, &stall, nullptr);
	std::this_thread::sleep_for(std::chrono::milliseconds(30));

	int rejected = 0;
	for (int i = 0; i < 200; ++i) {
		if (bfm_reset(session, BFM_RESET_NORMAL, nullptr) == BFM_ERR_QUEUE_FULL) {
			++rejected;
		}
	}
	check(rejected > 0, "the queue reports BFM_ERR_QUEUE_FULL once full");

	bfm_stats stats{};
	bfm_get_stats(session, &stats);
	check(stats.commands_rejected == static_cast<uint64_t>(rejected),
	      "rejected commands are counted");

	// 飽和したままでも停止できる。
	const auto begin = std::chrono::steady_clock::now();
	check(bfm_stop(session) == BFM_OK, "stop succeeds while the queue is saturated");
	const auto elapsed = std::chrono::steady_clock::now() - begin;
	check(elapsed < std::chrono::seconds(3), "stop completes promptly (no deadlock)");
	check(bfm_get_state(session) == BFM_STATE_STOPPED, "session ends stopped");

	bfm_destroy(session);
}

// --- Core thread: UI停止（イベントを引き取らない） ---
void test_ui_stall()
{
	std::printf("Core thread: a stalled UI drops old events, never blocks the core\n");

	constexpr uint32_t kEventCapacity = 16;
	bfm_session* session = make_session(256, kEventCapacity);
	bfm_start(session);
	wait_for_state(session, BFM_STATE_RUNNING, 3000);

	// UIは何もpollしないまま、コマンドだけを投げ続ける。
	for (int i = 0; i < 200; ++i) {
		bfm_reset(session, BFM_RESET_NORMAL, nullptr);
		std::this_thread::sleep_for(std::chrono::milliseconds(1));
	}

	bfm_stats before{};
	bfm_get_stats(session, &before);
	std::this_thread::sleep_for(std::chrono::milliseconds(100));
	bfm_stats after{};
	bfm_get_stats(session, &after);

	check(after.frames_run > before.frames_run, "the core kept running while the UI stalled");
	check(after.events_dropped > 0, "old events were dropped instead of growing the queue");

	int queued = 0;
	bfm_event event{};
	while (bfm_poll_event(session, &event) == BFM_OK) {
		++queued;
	}
	check(queued <= static_cast<int>(kEventCapacity), "the event queue stayed within its bound");

	check(bfm_stop(session) == BFM_OK, "stop succeeds after a UI stall");
	bfm_destroy(session);
}

} // namespace

int main(int argc, char* argv[])
{
	g_home = (argc > 1) ? argv[1] : ".";

	test_argument_validation();
	test_lifecycle();
	test_repeated_cycles();
	test_command_event_pairing();
	test_exception_containment();
	test_command_queue_saturation();
	test_ui_stall();

	if (failures != 0) {
		std::printf("\nsession spike FAILED (%d checks)\n", failures);
		return EXIT_FAILURE;
	}
	std::printf("\nsession spike passed\n");
	return EXIT_SUCCESS;
}
