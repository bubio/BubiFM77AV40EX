/*
 * 技術検証spikeの実装。詳細は bfm_session_spike.h のコメントを参照。
 *
 * 方針:
 *   - VMを触るのはCore threadだけ。C ABIの各関数はコマンド投入か
 *     スナップショット読出しに限る。
 *   - すべての公開関数を try/catch で包み、例外を境界外へ出さない。
 *   - コマンドキューとイベントキューは必ず上限を持つ。
 *     コマンドは飽和時に新しいものを拒否し（利用者操作の取りこぼしを明示）、
 *     イベントは飽和時に古いものから捨てる（UIの遅れでコアを止めない）。
 */
#include "bfm_session_spike.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <deque>
#include <mutex>
#include <new>
#include <stdexcept>
#include <thread>

#include "emu.h"

#include "core_host_symbols.h"

namespace {

constexpr uint32_t kDefaultCommandCapacity = 64;
constexpr uint32_t kDefaultEventCapacity = 256;

struct QueuedCommand {
	bfm_command command;
	uint64_t id;
};

} // namespace

struct bfm_session {
	// --- ホストとCore threadの両方から触る ---
	std::mutex mutex;
	std::condition_variable wake;
	std::deque<QueuedCommand> commands;
	std::deque<bfm_event> events;
	uint32_t command_capacity = kDefaultCommandCapacity;
	uint32_t event_capacity = kDefaultEventCapacity;

	std::atomic<bfm_state> state{BFM_STATE_STOPPED};
	std::atomic<bool> stop_requested{false};
	std::atomic<uint64_t> next_command_id{1};

	std::atomic<uint64_t> frames_run{0};
	std::atomic<uint64_t> commands_accepted{0};
	std::atomic<uint64_t> commands_rejected{0};
	std::atomic<uint64_t> events_dropped{0};

	std::thread core_thread;
	std::string home_dir;

	// --- Core threadだけが触る ---
	EMU* emu = nullptr;

	void push_event(const bfm_event& event)
	{
		std::lock_guard<std::mutex> lock(mutex);
		// UIがイベントを引き取らなくてもコアを止めない。古い順に捨てる。
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
		event.state = static_cast<int32_t>(next);
		push_event(event);
	}
};

namespace {

void complete_command(bfm_session* session, uint64_t id)
{
	bfm_event event{};
	event.kind = BFM_EVENT_COMMAND_COMPLETED;
	event.command_id = id;
	session->push_event(event);
}

void report_error(bfm_session* session, bfm_result code)
{
	bfm_event event{};
	event.kind = BFM_EVENT_ERROR;
	event.code = static_cast<int32_t>(code);
	session->push_event(event);
}

// Core threadだけが呼ぶ。VMへの操作はすべてここを通る。
void apply_command(bfm_session* session, VM_TEMPLATE* vm, const QueuedCommand& queued)
{
	switch (queued.command.kind) {
	case BFM_CMD_RESET:
		vm->reset();
		break;
	case BFM_CMD_SPECIAL_RESET:
		vm->special_reset();
		break;
	case BFM_CMD_SPIKE_STALL:
		// Core threadを意図的に滞留させ、コマンドキューを飽和させる。
		std::this_thread::sleep_for(std::chrono::milliseconds(queued.command.arg));
		break;
	case BFM_CMD_SPIKE_THROW:
		throw std::runtime_error("spike: exception raised on the core thread");
	default:
		break;
	}
	complete_command(session, queued.id);
}

void core_thread_main(bfm_session* session)
{
	using clock = std::chrono::steady_clock;

	try {
		// VMの生成から破棄までをCore threadに閉じる。
		bubi_core_set_home_dir(session->home_dir.c_str());
		session->emu = new EMU();
		VM_TEMPLATE* vm = session->emu->get_vm();
		if (vm == nullptr) {
			throw std::runtime_error("spike: VM was not constructed");
		}

		session->publish_state(BFM_STATE_RUNNING);

		const double frame_rate = vm->get_frame_rate();
		const auto frame_period = std::chrono::duration_cast<clock::duration>(
			std::chrono::duration<double>(1.0 / frame_rate));
		auto deadline = clock::now() + frame_period;

		while (!session->stop_requested.load()) {
			// 溜まったコマンドを先に処理する。
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

		session->publish_state(BFM_STATE_STOPPING);
		delete session->emu;
		session->emu = nullptr;
		session->publish_state(BFM_STATE_STOPPED);
	} catch (...) {
		// 例外をスレッド境界の外へ出さない。資源は必ず解放する。
		delete session->emu;
		session->emu = nullptr;
		report_error(session, BFM_ERR_CORE_FAILED);
		session->publish_state(BFM_STATE_FAILED);
	}
}

bfm_result enqueue(bfm_session* session, const bfm_command& command, uint64_t* out_id)
{
	const bfm_state state = session->state.load();
	if (state != BFM_STATE_RUNNING && state != BFM_STATE_STARTING) {
		return BFM_ERR_INVALID_STATE;
	}

	const uint64_t id = session->next_command_id.fetch_add(1);
	{
		std::lock_guard<std::mutex> lock(session->mutex);
		// 上限に達したら新しいコマンドを拒否する。古い操作を黙って捨てない。
		if (session->commands.size() >= session->command_capacity) {
			session->commands_rejected.fetch_add(1);
			return BFM_ERR_QUEUE_FULL;
		}
		session->commands.push_back(QueuedCommand{command, id});
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
		if (options == nullptr || options->home_dir == nullptr) {
			return BFM_ERR_INVALID_ARGUMENT;
		}

		bfm_session* session = new bfm_session();
		session->home_dir = options->home_dir;
		if (options->command_queue_capacity != 0) {
			session->command_capacity = options->command_queue_capacity;
		}
		if (options->event_queue_capacity != 0) {
			session->event_capacity = options->event_queue_capacity;
		}

		*out = session;
		return BFM_OK;
	} catch (const std::bad_alloc&) {
		return BFM_ERR_INTERNAL;
	} catch (...) {
		return BFM_ERR_INTERNAL;
	}
}

void bfm_destroy(bfm_session* session)
{
	if (session == nullptr) {
		return;   // 破棄は冪等。NULLも受け付ける。
	}
	try {
		bfm_stop(session);
		delete session;
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
		bfm_state expected = BFM_STATE_STOPPED;
		if (!session->state.compare_exchange_strong(expected, BFM_STATE_STARTING)) {
			return BFM_ERR_INVALID_STATE;   // 二重開始を弾く
		}
		session->stop_requested.store(false);
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
		return BFM_OK;   // 停止は冪等
	} catch (...) {
		return BFM_ERR_INTERNAL;
	}
}

bfm_result bfm_reset(bfm_session* session, bfm_reset_kind kind, uint64_t* out_command_id)
{
	if (session == nullptr) {
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

bfm_state bfm_get_state(bfm_session* session)
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
		return BFM_OK;
	} catch (...) {
		return BFM_ERR_INTERNAL;
	}
}

} // extern "C"
