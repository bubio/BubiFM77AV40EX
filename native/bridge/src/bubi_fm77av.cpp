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

#include "frame_ring.h"
#include "pcm_ring.h"

#include <dirent.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

#include <atomic>
#include <cctype>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <deque>
#include <mutex>
#include <new>
#include <stdexcept>
#include <string>
#include <thread>
#include <vector>

#include "common.h"
#include "emu.h"

#include "core_host_symbols.h"

namespace {

constexpr uint32_t kDefaultCommandCapacity = 64;
constexpr uint32_t kDefaultEventCapacity = 256;

/*
 * P0で受け付けるFDDドライブ数（FD1、FD2）。design.md 9.1・development_plan.md
 * WP5はFD1/FD2に限り、upstreamのUSE_FLOPPY_DISK（4）のうち先頭2つだけを使う。
 */
constexpr int64_t kFddDriveCount = 2;

/*
 * upstream の cpp_homedir はプロセス全域の変数であり、EMU の初回生成で
 * パスが確定する。同時に2つのセッションを持つと home_dir が競合するため、
 * 生存セッションを1つに制限する。複数セッションが必要になった時点で、
 * upstream を変更せずに分離する方法を改めて技術検証する。
 */
std::atomic<int> g_live_sessions{0};

/*
 * upstreamの get_application_path() は初回呼出しで値を固定する。
 * したがって home_dir はプロセス全体で1つに限る。最初の bfm_create で
 * 決め、以後は同じ値だけを受け付ける。
 */
std::mutex g_process_dirs_mutex;
std::string g_home_dir;
std::string g_core_dir;

/*
 * コアがそのディレクトリへ書き出すファイル。ROMディレクトリに同名の
 * ファイルがあってもリンクを張らない。張ると、コアの書込みが
 * シンボリックリンクを通って利用者のROMディレクトリを書き換える。
 */
const char* const kCoreWrittenFiles[] = {
	"USERDIC.DAT",   // 辞書学習データ
	"JCOMMCARD.bin", // 日本語通信カードのバックアップRAM
};

bool is_core_written_file(const char* name)
{
	for (const char* written : kCoreWrittenFiles) {
		if (strcasecmp(name, written) == 0) {
			return true;
		}
	}
	return false;
}

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

std::string to_upper(const std::string& value)
{
	std::string upper = value;
	for (char& c : upper) {
		c = static_cast<char>(toupper(static_cast<unsigned char>(c)));
	}
	return upper;
}

/*
 * core_dir/name から from へのシンボリックリンクを1つ張る。
 * 既に何かがある場合は触らない。実体ファイルを上書きしないため。
 */
bool link_one(const std::string& core_dir, const std::string& from,
              const std::string& name)
{
	const std::string to = core_dir + name;
	struct stat st;
	if (lstat(to.c_str(), &st) == 0) {
		return true; // 実体ファイルか既存リンクがある。上書きしない。
	}
	return symlink(from.c_str(), to.c_str()) == 0;
}

/*
 * コアがROMを読むディレクトリを、rom_dir の内容へ結線する。
 *
 * 原本は複製せずシンボリックリンクを張る（design.md 16.1）。
 * 張り直しでは既存のシンボリックリンクだけを消す。同じディレクトリに
 * USERDIC.DAT が実体で存在するため、通常ファイルを消すと利用者の
 * 辞書学習データを壊す。
 */
bool wire_rom_directory(const std::string& core_dir, const std::string& rom_dir)
{
	DIR* core = opendir(core_dir.c_str());
	if (core == nullptr) {
		return false;
	}
	// 先に古いリンクだけを外す。実体ファイルには触れない。
	for (struct dirent* entry = readdir(core); entry != nullptr; entry = readdir(core)) {
		const std::string name = entry->d_name;
		if (name == "." || name == "..") {
			continue;
		}
		const std::string path = core_dir + name;
		struct stat st;
		if (lstat(path.c_str(), &st) == 0 && S_ISLNK(st.st_mode)) {
			unlink(path.c_str());
		}
	}
	closedir(core);

	if (rom_dir.empty()) {
		return true; // ROM未設定。リンクなしで起動を試す。
	}

	DIR* source = opendir(rom_dir.c_str());
	if (source == nullptr) {
		return false;
	}
	bool ok = true;
	for (struct dirent* entry = readdir(source); entry != nullptr;
	     entry = readdir(source)) {
		const std::string name = entry->d_name;
		if (name == "." || name == "..") {
			continue;
		}
		if (is_core_written_file(name.c_str())) {
			continue;
		}
		const std::string from = rom_dir + "/" + name;
		struct stat st;
		if (stat(from.c_str(), &st) != 0 || !S_ISREG(st.st_mode)) {
			continue; // ディレクトリと壊れたリンクは無視する
		}
		// コアは大文字の名前で開く（fm7_common.h の ROM_* 定義）。
		// 利用者のファイルが小文字でも読めるよう、元の名前と
		// 大文字化した名前の両方でリンクを張る。macOSは大小文字を
		// 区別しない設定が既定なので片方で足りるが、Linuxでは
		// 大文字側がないとコアがROMを1つも読めない。
		if (!link_one(core_dir, from, name)) {
			ok = false;
			break;
		}
		const std::string upper = to_upper(name);
		if (upper != name && !link_one(core_dir, from, upper)) {
			ok = false;
			break;
		}
	}
	closedir(source);
	return ok;
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
	std::atomic<uint64_t> frames_published{0};

	/*
	 * 次のフレームを無条件に公開する。起動直後とリセット直後に立てる。
	 * コアが画面へ触るまで is_screen_changed() はfalseを返し続けるため、
	 * これがないと画面が真っ黒のままになる。
	 */
	std::atomic<bool> force_publish{true};

	std::thread core_thread;
	std::string home_dir;
	std::string core_dir; // コアがROMを読み USERDIC.DAT を書く位置
	std::string rom_dir;  // 利用者が選んだROMディレクトリ（空なら未設定）
	int32_t boot_mode = BFM_BOOT_BASIC;

	// VM操作を許されたスレッド。Core threadの起動直後に確定する。
	std::atomic<bool> core_thread_id_valid{false};
	std::thread::id core_thread_id;

	// 映像。Core threadが書き、描画側が借りる。
	bubi::FrameRing frames;

	// 音声。Core threadが書き、bfm_read_audioの呼び手が読む。
	// EMU/OSDの寿命とは独立に生きる（pcm_ring.h）。
	bubi::PcmRing audio;
	std::atomic<uint64_t> audio_frames_produced{0};

	// 直近に公開した解像度。Core threadだけが書く。
	int screen_width = 0;
	int screen_height = 0;

	// 直近に通知したLED。初期値は「まだ読んでいない」を表す。
	uint32_t led_status = 0xffffffffu;

	/*
	 * FD1/FD2アクセス状態の累積ビット。Core threadが毎フレームORで
	 * 足し込み、bfm_get_media_accessを呼んだ側がexchangeで読み取って
	 * 0へ戻す（read-and-clear）。VM::is_floppy_disk_accessed()
	 * （MB8877::read_signal）自体が呼ぶたびにフラグを消費する
	 * read-and-clearであり、Core thread以外から直接読めないため、
	 * 単一の読み手（Core thread）が積算し、複数の消費者（Dartの
	 * ポーリング）はここを介して安全に読む。
	 */
	std::atomic<uint32_t> media_access_bits{0};

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
		// リセット直後はコアが画面へ触るまで is_screen_changed() が
		// falseを返し続ける。1枚出さないと古い画面が残る。
		session->force_publish.store(true);
		break;
	case BFM_CMD_SPECIAL_RESET:
		vm->special_reset();
		session->force_publish.store(true);
		break;
	case BFM_CMD_KEY_DOWN:
	case BFM_CMD_KEY_UP: {
		// コードは win32 の仮想キーコード。コアの vk_matrix_106
		// （vm/fm7/keyboard_tables.h）がこれを走査コードへ変換する。
		// 変換表そのものがコアの都合なので、対応表はホスト側に置く。
		if (queued.arg0 < 0 || queued.arg0 > 0xff) {
			code = BFM_ERR_INVALID_ARGUMENT;
			break;
		}
		const int key_code = static_cast<int>(queued.arg0);
		// EMU::key_down は宣言だけで実体が win32 側にある。
		// ここではコアが持つOSDを直接呼ぶ。
		OSD* osd = session->emu->get_osd();
		if (osd == nullptr) {
			code = BFM_ERR_INTERNAL;
			break;
		}
		if (queued.kind == BFM_CMD_KEY_DOWN) {
			// リピートはホスト側で落とす。コアへ二重に送らない（INP-01）。
			osd->key_down(key_code, false, false);
		} else {
			osd->key_up(key_code, false);
		}
		break;
	}
	case BFM_CMD_INSERT_FDD: {
		// design.md 9.1: D88/D77/D8E/1DDだけを対象とする。呼び出し側が
		// 書き戻し用の作業コピーを用意して text へ渡す（原本には触れない）。
		if (queued.arg0 < 0 || queued.arg0 >= kFddDriveCount || queued.arg1 < 0 ||
		    queued.text.empty()) {
			code = BFM_ERR_INVALID_ARGUMENT;
			break;
		}
		const int drv = static_cast<int>(queued.arg0);
		if (session->emu->is_floppy_disk_inserted(drv)) {
			// 二重挿入は拒否する。upstreamのEMU::open_floppy_diskは
			// 挿入済みなら自動排出してから0.5秒待つ実機の間合いを再現するが、
			// 書き戻しの完了を呼び出し側が観測できなくなるため使わない。
			code = BFM_ERR_INVALID_STATE;
			break;
		}
		session->emu->open_floppy_disk(drv, queued.text.c_str(), static_cast<int>(queued.arg1));
		if (!session->emu->is_floppy_disk_inserted(drv)) {
			// コアが形式を受理しなかった（不正なD88など）。
			code = BFM_ERR_INVALID_ARGUMENT;
			break;
		}
		bfm_event event{};
		event.kind = BFM_EVENT_MEDIA_CHANGED;
		event.arg0 = drv;
		event.arg1 = 1;
		session->push_event(event);
		break;
	}
	case BFM_CMD_EJECT_FDD: {
		if (queued.arg0 < 0 || queued.arg0 >= kFddDriveCount) {
			code = BFM_ERR_INVALID_ARGUMENT;
			break;
		}
		const int drv = static_cast<int>(queued.arg0);
		if (!session->emu->is_floppy_disk_inserted(drv)) {
			// 未挿入のドライブへの排出は冪等にOKとする（bfm_stopと同じ方針）。
			break;
		}
		// close_floppy_diskは同期的にDISK::close()を呼び、変更があれば
		// ここで書き戻しを終える。戻った時点で呼び出し側は作業コピーの
		// 内容を原本へ原子的に反映してよい。
		session->emu->close_floppy_disk(drv);
		bfm_event event{};
		event.kind = BFM_EVENT_MEDIA_CHANGED;
		event.arg0 = drv;
		event.arg1 = 0;
		session->push_event(event);
		break;
	}
	case BFM_CMD_SET_BOOT_MODE:
		// コアはリセット時に config.boot_mode を読む。ここでは値を
		// 置くだけで、反映は次のリセットまたは再起動になる（SYS-04）。
		if (queued.arg0 != BFM_BOOT_BASIC && queued.arg0 != BFM_BOOT_DOS) {
			code = BFM_ERR_INVALID_ARGUMENT;
		} else {
			config.boot_mode = static_cast<int>(queued.arg0);
		}
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

/*
 * 画面が変わっていれば1枚公開する。
 *
 * VM::is_screen_changed() は読むと状態を落とす（display->screen_update() の
 * 直後に reset_screen_update() を呼ぶ）。1フレームにつき1回だけ呼び、
 * 戻り値を必ず使うこと。2回目はfalseを返し、捨てた更新は戻らない。
 */
void publish_frame_if_changed(bfm_session* session, VM_TEMPLATE* vm)
{
	session->note_vm_access();
	const bool changed = vm->is_screen_changed();
	// is_screen_changed() は必ず1回だけ呼び、戻り値を必ず使う。
	// 読むと状態が落ちるため、捨てた更新は戻らない。
	const bool forced = session->force_publish.exchange(false);
	if (!changed && !forced) {
		return; // VID-07 フレーム更新のない期間は転送しない
	}

	session->note_vm_access();
	session->emu->draw_screen();
	OSD* osd = session->emu->get_osd();
	const int width = osd->get_vm_screen_width();
	const int height = osd->get_vm_screen_height();
	if (width <= 0 || height <= 0) {
		return;
	}

	// 解像度が変わったらUIへ知らせる（design.md 4.3 screenModeChanged）。
	// 表示側は縦横比と拡大率をこれで決める（VID-02）。
	if (session->screen_width != width || session->screen_height != height) {
		session->screen_width = width;
		session->screen_height = height;
		bfm_event event{};
		event.kind = BFM_EVENT_SCREEN_MODE_CHANGED;
		event.arg0 = width;
		event.arg1 = height;
		session->push_event(event);
	}

	const uint64_t before = session->frames.dropped();
	session->frames.publish(
		static_cast<uint32_t>(width), static_cast<uint32_t>(height),
		[session, width](uint32_t* dst, uint32_t y) {
			const scrntype_t* row = session->emu->get_screen_buffer(static_cast<int>(y));
			if (row == nullptr) {
				for (int x = 0; x < width; ++x) {
					dst[x] = 0xff000000u;
				}
				return;
			}
			// コアの RGB_COLOR はアルファを書かない。0のままだと
			// 画面全体が背景と混ざる（design.md 16.1）。
			for (int x = 0; x < width; ++x) {
				dst[x] = static_cast<uint32_t>(row[x]) | 0xff000000u;
			}
		});
	if (session->frames.dropped() == before) {
		session->frames_published.fetch_add(1);
	}
}

/*
 * INS / KANA / CAPS のLEDが変わったらUIへ知らせる（INP-02）。
 * ビットは vm/fm7/keyboard.cpp の SIG_FM7KEY_LED_STATUS が決めており、
 * 0x1=INS、0x2=KANA、0x4=CAPS である。
 */
void publish_led_if_changed(bfm_session* session, VM_TEMPLATE* vm)
{
	session->note_vm_access();
	const uint32_t status = vm->get_led_status();
	if (status == session->led_status) {
		return;
	}
	session->led_status = status;
	bfm_event event{};
	event.kind = BFM_EVENT_LED_CHANGED;
	event.arg0 = static_cast<int64_t>(status);
	session->push_event(event);
}

/*
 * FD1/FD2のアクセス状態（design.md WP5「アクセス状態」）。
 *
 * LEDとは違い、VM::is_floppy_disk_accessed()（MB8877::read_signal、
 * ch以外の分岐）は読むたびに各ドライブのaccessフラグを消費して
 * falseへ戻すread-and-clearである。publish_led_if_changedと同じ
 * 「変わっていれば通知する」を単純に適用すると、実アクセス中は
 * 1フレームおきに立って落ちる高頻度イベントになり、design.md 4.3が
 * 禁じる高頻度データをイベントキューへ流してしまう
 * （256件で古いものから捨てる設計のため events_dropped を押し上げる）。
 *
 * そのためイベントにはせず、毎フレームORで累積するだけにとどめ、
 * 消費（read-and-clear）は bfm_get_media_access を呼んだ側（Dartの
 * UIレート・ポーリング）に委ねる。
 */
void accumulate_media_access(bfm_session* session, VM_TEMPLATE* vm)
{
	(void)vm;
	session->note_vm_access();
	const uint32_t status = session->emu->is_floppy_disk_accessed();
	if (status != 0) {
		session->media_access_bits.fetch_or(status);
	}
}

/*
 * design.md 16.1「音声はVMの駆動源にしない」。
 *
 * vm->create_sound()は要求した分（kAudioSamplesPerCall）が
 * event->buffer_ptr に溜まるまで内部でdrive()を呼び足す（vm/event.cpp）。
 * buffer_ptrは毎tickのvm->run()が進める通常のクロックでも増え続けるため、
 * 溜まるのを待ってから呼べば内部driveは0で済み、壁時計のvm->run()だけが
 * VMを進める唯一の駆動源であり続ける。
 *
 * vm->get_sound_buffer_ptr()未満のあいだは呼ばない。EMU::EMU()が
 * config.sound_frequency/sound_latencyからsound_samplesを決めて
 * vm->initialize_sound()を1度だけ呼ぶため（emu.cpp）、ここで
 * vm->initialize_sound()を呼び直すと同じ周期のEVENT_MIXが二重登録され
 * ミキシングが二重になる。よってbridge側はconfigを見て同じ式
 * （kAudioSamplesPerCall、pcm_ring.h）で追認するだけにとどめる。
 */
void publish_audio_if_ready(bfm_session* session, VM_TEMPLATE* vm)
{
	session->note_vm_access();
	if (vm->get_sound_buffer_ptr() < bubi::kAudioSamplesPerCall) {
		return;
	}
	int extra_frames = 0;
	uint16_t* buffer = vm->create_sound(&extra_frames);
	session->audio.push(reinterpret_cast<const int16_t*>(buffer),
	                    static_cast<std::size_t>(bubi::kAudioSamplesPerCall));
	session->audio_frames_produced.fetch_add(
	    static_cast<uint64_t>(bubi::kAudioSamplesPerCall));
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

		// ROMを1つのディレクトリへ結線してから EMU を作る。
		// コアは生成時にROMを読むため、順序を入れ替えられない。
		if (!home_dir_is_writable(session->core_dir)) {
			throw std::runtime_error("core directory is not writable");
		}
		if (!wire_rom_directory(session->core_dir, session->rom_dir)) {
			throw std::runtime_error("failed to wire the ROM directory");
		}

		// VMの生成から破棄までをCore threadに閉じる。
		bubi_core_set_home_dir(session->home_dir.c_str());
		config.boot_mode = session->boot_mode;
		/*
		 * design.md 7。configは既定で0初期化のままだと
		 * sound_frequency_table[0]=2000Hzになる（emu.cpp）。48kHz固定
		 * （pcm_ring.h kAudioSampleRate）を明示し、latencyは
		 * kAudioSamplesPerCallと同じ式になるsound_latency_table[1]
		 * （0.1秒）を選ぶ。
		 */
		config.sound_frequency = 6; // 48kHz
		config.sound_latency = 1;   // 0.1秒
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

			publish_frame_if_changed(session, vm);
			publish_led_if_changed(session, vm);
			accumulate_media_access(session, vm);
			publish_audio_if_ready(session, vm);


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

		if (options->boot_mode != BFM_BOOT_BASIC && options->boot_mode != BFM_BOOT_DOS) {
			return BFM_ERR_INVALID_ARGUMENT;
		}

		// 生存セッションは1つに限る（理由は g_live_sessions のコメント）。
		int expected = 0;
		if (!g_live_sessions.compare_exchange_strong(expected, 1)) {
			return BFM_ERR_INVALID_STATE;
		}

		std::string core_dir;
		{
			std::lock_guard<std::mutex> lock(g_process_dirs_mutex);
			if (g_home_dir.empty()) {
				// 初回だけ upstream に解決させる。以後は同じ値が返るため、
				// ここで写しを持って再呼出しを避ける。
				g_home_dir = options->home_dir;
				bubi_core_set_home_dir(g_home_dir.c_str());
				g_core_dir = get_application_path();
			} else if (g_home_dir != options->home_dir) {
				// upstream が初回の値を固定しているため、変えても効かない。
				// 黙って別の場所を読ませるより、明示的に拒否する。
				g_live_sessions.store(0);
				return BFM_ERR_INVALID_STATE;
			}
			core_dir = g_core_dir;
		}

		bfm_session* session = nullptr;
		try {
			session = new bfm_session();
		} catch (...) {
			g_live_sessions.store(0);
			throw;
		}
		session->home_dir = options->home_dir;
		session->core_dir = core_dir;
		session->boot_mode = options->boot_mode;
		if (options->rom_dir != nullptr) {
			session->rom_dir = options->rom_dir;
		}
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

bfm_result bfm_get_core_directory(bfm_session* session, char* out, uint32_t out_size)
{
	if (session == nullptr || out == nullptr || out_size == 0) {
		return BFM_ERR_INVALID_ARGUMENT;
	}
	try {
		if (session->core_dir.size() + 1 > out_size) {
			return BFM_ERR_INVALID_ARGUMENT;
		}
		std::memcpy(out, session->core_dir.c_str(), session->core_dir.size() + 1);
		return BFM_OK;
	} catch (...) {
		return BFM_ERR_INTERNAL;
	}
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
		out->frames_published = session->frames_published.load();
		out->frames_dropped = session->frames.dropped();
		out->audio_frames_produced = session->audio_frames_produced.load();
		out->audio_underrun_frames = session->audio.total_underrun_frames();
		out->audio_overrun_frames = session->audio.total_overrun_frames();
		return BFM_OK;
	} catch (...) {
		return BFM_ERR_INTERNAL;
	}
}

BFM_API bfm_result bfm_read_audio(bfm_session* session, int16_t* out, uint32_t frame_capacity)
{
	if (session == nullptr || out == nullptr) {
		return BFM_ERR_INVALID_ARGUMENT;
	}
	session->audio.pop(out, frame_capacity);
	return BFM_OK;
}

/*
 * FD1/FD2アクセス状態のread-and-clearポーリング（design.md WP5、
 * accumulate_media_accessの注記）。ビット0=FD1、ビット1=FD2。
 * 呼ぶたびに累積を0へ戻すため、消費者は1つに保つこと。
 */
BFM_API bfm_result bfm_get_media_access(bfm_session* session, uint32_t* out_bits)
{
	if (session == nullptr || out_bits == nullptr) {
		return BFM_ERR_INVALID_ARGUMENT;
	}
	*out_bits = session->media_access_bits.exchange(0);
	return BFM_OK;
}

BFM_API bfm_result bfm_get_audio_format(bfm_session* session, uint32_t* out_sample_rate,
                                        uint32_t* out_channels)
{
	if (session == nullptr || out_sample_rate == nullptr || out_channels == nullptr) {
		return BFM_ERR_INVALID_ARGUMENT;
	}
	*out_sample_rate = static_cast<uint32_t>(bubi::kAudioSampleRate);
	*out_channels = static_cast<uint32_t>(bubi::kAudioChannels);
	return BFM_OK;
}

BFM_API bfm_result bfm_acquire_video_frame(bfm_session* session, bfm_video_frame* out)
{
	if (session == nullptr || out == nullptr) {
		return BFM_ERR_INVALID_ARGUMENT;
	}
	bubi::FrameView view;
	if (!session->frames.acquire(&view)) {
		return BFM_ERR_NO_EVENT;
	}
	out->pixels = view.pixels;
	out->width = view.width;
	out->height = view.height;
	out->reserved = 0;
	out->generation = view.generation;
	return BFM_OK;
}

BFM_API void bfm_release_video_frame(bfm_session* session, uint64_t generation)
{
	if (session != nullptr) {
		session->frames.release(generation);
	}
}

BFM_API uint64_t bfm_video_generation(bfm_session* session)
{
	return (session == nullptr) ? 0 : session->frames.published_generation();
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
