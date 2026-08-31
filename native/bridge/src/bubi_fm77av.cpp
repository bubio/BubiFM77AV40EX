/*
 * 製品用 C ABI の実装（design.md 4.1〜4.3、5.1、16.1）。
 *
 * 不変条件:
 *   - VMを生成・操作・破棄するのはCore threadだけ。C ABIの各関数は
 *     コマンド投入かスナップショット読出しに限る。
 *   - 公開関数はすべて try/catch(...) で包み、例外を境界外へ出さない。
 *   - コマンドキューは飽和時に新しいコマンドを拒否する（利用者操作を
 *     黙って捨てない）。イベントキューは飽和時に古いものから捨てる
 *     （UIの遅れでコアを止めない）。
 */
#include "bubi_fm77av.h"

#include <sys/stat.h>
#include <sys/types.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <deque>
#include <mutex>
#include <new>
#include <stdexcept>
#include <string>
#include <thread>

#include "emu.h"

#include "core_host_symbols.h"

namespace {

constexpr uint32_t kDefaultCommandCapacity = 64;
constexpr uint32_t kDefaultEventCapacity = 256;

/*
 * upstream の cpp_homedir はプロセス全域の変数であり、EMU の初回生成で
 * パスが確定する。同時に2つのセッションを持つと home_dir が競合するため、
 * 生存セッションを1つに制限する。複数セッションが必要になった時点で、
 * upstream を変更せずに分離する方法を改めて技術検証する。
 */
std::atomic<int> g_live_sessions{0};

struct QueuedCommand {
	uint32_t kind;
	int64_t arg0;
	int64_t arg1;
	std::string text; // 呼び出し中に複製する。借用ポインターを保持しない。
	uint64_t id;
};

// 親ディレクトリを含めて作る。既存なら何もしない。
bool ensure_directory(const std::string& path)
{
	if (path.empty()) {
		return false;
	}
	for (std::string::size_type i = 1; i <= path.size(); ++i) {
		if (i != path.size() && path[i] != '/') {
			continue;
		}
		const std::string part = path.substr(0, i);
		struct stat st;
		if (stat(part.c_str(), &st) == 0) {
			if (!S_ISDIR(st.st_mode)) {
				return false;
			}
			continue;
		}
		if (mkdir(part.c_str(), 0700) != 0) {
			return false;
		}
	}
	return true;
}

/*
 * home_dir が実際に書けることを EMU 生成前に確かめる。
 * コアは書込みに失敗しても継続してしまうため、ここで検出しないと
 * 「起動したのに設定も辞書も保存されない」状態になる。
 * 初期化失敗の経路はこの検査で試験する（development_plan.md 6 WP1）。
 */
bool home_dir_is_writable(const std::string& home_dir)
{
	if (!ensure_directory(home_dir)) {
		return false;
	}
	const std::string probe = home_dir + "/.bubi_write_probe";
	FILE* fp = fopen(probe.c_str(), "wb");
	if (fp == nullptr) {
		return false;
	}
	const bool wrote = fwrite("0", 1, 1, fp) == 1;
	fclose(fp);
	remove(probe.c_str());
	return wrote;
}

} // namespace

struct bfm_session {
	// --- ホストとCore threadの両方から触る ---
	std::mutex mutex;
	std::condition_variable wake;
	std::deque<QueuedCommand> commands;
	std::deque<bfm_event> events;
	uint32_t command_capacity = kDefaultCommandCapacity;
	uint32_t event_capacity = kDefaultEventCapacity;

	std::atomic<int32_t> state{BFM_STATE_STOPPED};
	std::atomic<bool> stop_requested{false};
	std::atomic<uint64_t> next_command_id{1};

	std::atomic<uint64_t> frames_run{0};
	std::atomic<uint64_t> commands_accepted{0};
	std::atomic<uint64_t> commands_rejected{0};
	std::atomic<uint64_t> events_dropped{0};
	std::atomic<uint64_t> vm_access_violations{0};

	std::thread core_thread;
	std::string home_dir;

	// VM操作を許されたスレッド。Core threadの起動直後に確定する。
	std::atomic<bool> core_thread_id_valid{false};
	std::thread::id core_thread_id;

	// --- Core threadだけが触る ---
	EMU* emu = nullptr;

	/*
	 * VMへ触る直前に必ず呼ぶ。Core thread以外だった場合は数えるだけで
	 * 処理は止めない。テストは bfm_stats.vm_access_violations が0で
	 * あることを確認する。
	 */
	void note_vm_access()
	{
		if (!core_thread_id_valid.load() || core_thread_id != std::this_thread::get_id()) {
			vm_access_violations.fetch_add(1);
		}
	}

	void push_event(const bfm_event& event)
	{
		std::lock_guard<std::mutex> lock(mutex);
		while (events.size() >= event_capacity) {
			events.pop_front();
			events_dropped.fetch_add(1);
		}
		events.push_back(event);
	}

	void publish_state(bfm_state next)
	{
		state.store(next);
		bfm_event event{};
		event.kind = BFM_EVENT_LIFECYCLE_CHANGED;
		event.arg0 = static_cast<int64_t>(next);
		push_event(event);
	}

	void complete_command(uint64_t id, bfm_result code)
	{
		bfm_event event{};
		event.kind = BFM_EVENT_COMMAND_COMPLETED;
		event.command_id = id;
		event.code = static_cast<int32_t>(code);
		push_event(event);
	}

	void report_error(bfm_result code)
	{
		bfm_event event{};
		event.kind = BFM_EVENT_ERROR;
		event.code = static_cast<int32_t>(code);
		push_event(event);
	}
};

namespace {

// Core threadだけが呼ぶ。VMへの操作はすべてここを通る。
void apply_command(bfm_session* session, VM_TEMPLATE* vm, const QueuedCommand& queued)
{
	session->note_vm_access();

	bfm_result code = BFM_OK;
	switch (queued.kind) {
	case BFM_CMD_RESET:
		vm->reset();
		break;
	case BFM_CMD_SPECIAL_RESET:
		vm->special_reset();
		break;
	default:
		// 型として定義済みだが未実装。担当WPは bubi_fm77av.h を参照。
		code = BFM_ERR_UNSUPPORTED;
		break;
	}
	session->complete_command(queued.id, code);
}

/*
 * キューに残ったコマンドを code で完了させる。
 *
 * 完了通知を出さないまま捨てると、同じIDの commandCompleted を待つ
 * 呼び出し側が永久に待つ。停止と初期化失敗の両方で必ず通す。
 * 呼ぶ前に state を RUNNING/STARTING 以外へ移し、enqueue が
 * 新しいコマンドを受け付けない状態にしておくこと。
 */
void drain_pending_commands(bfm_session* session, bfm_result code)
{
	for (;;) {
		QueuedCommand queued;
		{
			std::lock_guard<std::mutex> lock(session->mutex);
			if (session->commands.empty()) {
				return;
			}
			queued = session->commands.front();
			session->commands.pop_front();
		}
		session->complete_command(queued.id, code);
	}
}

void core_thread_main(bfm_session* session)
{
	using clock = std::chrono::steady_clock;

	session->core_thread_id = std::this_thread::get_id();
	session->core_thread_id_valid.store(true);

	try {
		if (!home_dir_is_writable(session->home_dir)) {
			throw std::runtime_error("home_dir is not writable");
		}

		// VMの生成から破棄までをCore threadに閉じる。
		bubi_core_set_home_dir(session->home_dir.c_str());
		session->note_vm_access();
		session->emu = new EMU();
		VM_TEMPLATE* vm = session->emu->get_vm();
		if (vm == nullptr) {
			throw std::runtime_error("VM was not constructed");
		}

		session->publish_state(BFM_STATE_RUNNING);

		const double frame_rate = vm->get_frame_rate();
		const auto frame_period = std::chrono::duration_cast<clock::duration>(
			std::chrono::duration<double>(1.0 / frame_rate));
		auto deadline = clock::now() + frame_period;

		while (!session->stop_requested.load()) {
			for (;;) {
				QueuedCommand queued;
				{
					std::lock_guard<std::mutex> lock(session->mutex);
					if (session->commands.empty()) {
						break;
					}
					queued = session->commands.front();
					session->commands.pop_front();
				}
				apply_command(session, vm, queued);
			}

			session->note_vm_access();
			vm->run();
			session->frames_run.fetch_add(1);

			// 単調増加時計で次回期限を決める。遅れたら取り戻さず基準へ戻す。
			const auto now = clock::now();
			if (now < deadline) {
				std::this_thread::sleep_until(deadline);
				deadline += frame_period;
			} else {
				deadline = now + frame_period;
			}
		}

		// STOPPING にしてから引き取る。以後 enqueue は invalidState で拒否され、
		// 取りこぼしの窓が開かない。
		session->publish_state(BFM_STATE_STOPPING);
		drain_pending_commands(session, BFM_ERR_INVALID_STATE);
		session->note_vm_access();
		delete session->emu;
		session->emu = nullptr;
		session->publish_state(BFM_STATE_STOPPED);
	} catch (...) {
		// 例外をスレッド境界の外へ出さない。資源は必ず解放する。
		delete session->emu;
		session->emu = nullptr;
		session->report_error(BFM_ERR_CORE_FAILED);
		session->publish_state(BFM_STATE_FAILED);
		// STARTING の間に受理したコマンドを未完了のまま残さない。
		drain_pending_commands(session, BFM_ERR_CORE_FAILED);
	}
}

bfm_result enqueue(bfm_session* session, const bfm_command& command, uint64_t* out_id)
{
	const int32_t state = session->state.load();
	if (state != BFM_STATE_RUNNING && state != BFM_STATE_STARTING) {
		return BFM_ERR_INVALID_STATE;
	}

	QueuedCommand queued;
	queued.kind = command.kind;
	queued.arg0 = command.arg0;
	queued.arg1 = command.arg1;
	if (command.text != nullptr) {
		queued.text = command.text; // 借用ポインターを保持しない
	}
	const uint64_t id = session->next_command_id.fetch_add(1);
	queued.id = id;

	{
		std::lock_guard<std::mutex> lock(session->mutex);
		if (session->commands.size() >= session->command_capacity) {
			session->commands_rejected.fetch_add(1);
			return BFM_ERR_QUEUE_FULL;
		}
		session->commands.push_back(std::move(queued));
	}
	session->commands_accepted.fetch_add(1);
	session->wake.notify_all();

	if (out_id != nullptr) {
		*out_id = id;
	}
	return BFM_OK;
}

} // namespace

extern "C" {

bfm_result bfm_create(const bfm_create_options* options, bfm_session** out)
{
	if (out == nullptr) {
		return BFM_ERR_INVALID_ARGUMENT;
	}
	try {
		if (options == nullptr || options->home_dir == nullptr
			|| options->home_dir[0] == '\0') {
			return BFM_ERR_INVALID_ARGUMENT;
		}

		// 生存セッションは1つに限る（理由は g_live_sessions のコメント）。
		int expected = 0;
		if (!g_live_sessions.compare_exchange_strong(expected, 1)) {
			return BFM_ERR_INVALID_STATE;
		}

		bfm_session* session = nullptr;
		try {
			session = new bfm_session();
		} catch (...) {
			g_live_sessions.store(0);
			throw;
		}
		session->home_dir = options->home_dir;
		if (options->command_queue_capacity != 0) {
			session->command_capacity = options->command_queue_capacity;
		}
		if (options->event_queue_capacity != 0) {
			session->event_capacity = options->event_queue_capacity;
		}

		*out = session;
		return BFM_OK;
	} catch (...) {
		return BFM_ERR_INTERNAL;
	}
}

void bfm_destroy(bfm_session* session)
{
	if (session == nullptr) {
		return; // 破棄は冪等。NULLも受け付ける。
	}
	try {
		bfm_stop(session);
		delete session;
		g_live_sessions.store(0);
	} catch (...) {
		// 破棄経路から例外を出さない。
	}
}

bfm_result bfm_start(bfm_session* session)
{
	if (session == nullptr) {
		return BFM_ERR_INVALID_ARGUMENT;
	}
	try {
		int32_t expected = BFM_STATE_STOPPED;
		if (!session->state.compare_exchange_strong(expected, BFM_STATE_STARTING)) {
			return BFM_ERR_INVALID_STATE; // 二重開始を弾く
		}
		session->stop_requested.store(false);
		session->core_thread_id_valid.store(false);
		session->core_thread = std::thread(core_thread_main, session);
		return BFM_OK;
	} catch (...) {
		session->state.store(BFM_STATE_FAILED);
		return BFM_ERR_INTERNAL;
	}
}

bfm_result bfm_stop(bfm_session* session)
{
	if (session == nullptr) {
		return BFM_ERR_INVALID_ARGUMENT;
	}
	try {
		session->stop_requested.store(true);
		session->wake.notify_all();
		if (session->core_thread.joinable()) {
			session->core_thread.join();
		}
		return BFM_OK; // 停止は冪等
	} catch (...) {
		return BFM_ERR_INTERNAL;
	}
}

bfm_result bfm_reset(bfm_session* session, bfm_reset_kind kind, uint64_t* out_command_id)
{
	if (session == nullptr) {
		return BFM_ERR_INVALID_ARGUMENT;
	}
	if (kind != BFM_RESET_NORMAL && kind != BFM_RESET_SPECIAL) {
		return BFM_ERR_INVALID_ARGUMENT;
	}
	try {
		bfm_command command{};
		command.kind = (kind == BFM_RESET_SPECIAL) ? BFM_CMD_SPECIAL_RESET : BFM_CMD_RESET;
		return enqueue(session, command, out_command_id);
	} catch (...) {
		return BFM_ERR_INTERNAL;
	}
}

bfm_result bfm_send_command(bfm_session* session, const bfm_command* command,
                            uint64_t* out_command_id)
{
	if (session == nullptr || command == nullptr) {
		return BFM_ERR_INVALID_ARGUMENT;
	}
	try {
		return enqueue(session, *command, out_command_id);
	} catch (...) {
		return BFM_ERR_INTERNAL;
	}
}

bfm_result bfm_poll_event(bfm_session* session, bfm_event* out)
{
	if (session == nullptr || out == nullptr) {
		return BFM_ERR_INVALID_ARGUMENT;
	}
	try {
		std::lock_guard<std::mutex> lock(session->mutex);
		if (session->events.empty()) {
			return BFM_ERR_NO_EVENT;
		}
		*out = session->events.front();
		session->events.pop_front();
		return BFM_OK;
	} catch (...) {
		return BFM_ERR_INTERNAL;
	}
}

int32_t bfm_get_state(bfm_session* session)
{
	return (session == nullptr) ? BFM_STATE_STOPPED : session->state.load();
}

bfm_result bfm_get_stats(bfm_session* session, bfm_stats* out)
{
	if (session == nullptr || out == nullptr) {
		return BFM_ERR_INVALID_ARGUMENT;
	}
	try {
		out->frames_run = session->frames_run.load();
		out->commands_accepted = session->commands_accepted.load();
		out->commands_rejected = session->commands_rejected.load();
		out->events_dropped = session->events_dropped.load();
		out->vm_access_violations = session->vm_access_violations.load();
		return BFM_OK;
	} catch (...) {
		return BFM_ERR_INTERNAL;
	}
}

#ifdef BUBI_ENABLE_TEST_HOOKS
/*
 * テスト専用。テストバイナリにだけ含める（配布物には入らない）。
 * VM操作の見張り（note_vm_access）そのものが機能していることを確かめる。
 * VMには触れずガードだけを呼ぶので、実際のデータ競合は起こさない。
 */
BFM_API void bfm_test_touch_vm_guard_from_caller_thread(bfm_session* session)
{
	if (session != nullptr) {
		session->note_vm_access();
	}
}
#endif

} // extern "C"
