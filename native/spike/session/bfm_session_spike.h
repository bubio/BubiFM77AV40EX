/*
 * 技術検証spike（development_plan.md 5.3「C ABI」「Core thread」）。
 *
 * これは破棄可能な最小検証であり、製品コードではない。確認するのは次だけ:
 *   - 不透明ハンドルと所有権（確保側が解放する）
 *   - 例外を境界外へ出さないこと
 *   - コマンドとイベントの対応（連番IDで完了通知）
 *   - Core threadだけがVMを操作すること
 *   - 停止要求とキュー上限（UI停止・キュー飽和でも安全に停止できる）
 *
 * design.md 4.1 の宣言案を出発点にしているが、確定版ではない。
 * 検証結果を design.md へ反映したうえで、M1 WP1 で製品用に作り直す。
 */
#ifndef BFM_SESSION_SPIKE_H_
#define BFM_SESSION_SPIKE_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* 不透明ハンドル。C++型をDartへ露出しない。 */
typedef struct bfm_session bfm_session;

typedef enum {
	BFM_OK = 0,
	BFM_ERR_INVALID_ARGUMENT = 1,
	BFM_ERR_INVALID_STATE = 2,   /* 二重開始、停止中の操作など */
	BFM_ERR_QUEUE_FULL = 3,      /* コマンドキューが上限に達した */
	BFM_ERR_NO_EVENT = 4,        /* poll時にイベントがない */
	BFM_ERR_CORE_FAILED = 5,     /* Core thread内で異常が発生した */
	BFM_ERR_INTERNAL = 6         /* 境界で捕捉した想定外の例外 */
} bfm_result;

typedef enum {
	BFM_STATE_STOPPED = 0,
	BFM_STATE_STARTING = 1,
	BFM_STATE_RUNNING = 2,
	BFM_STATE_STOPPING = 3,
	BFM_STATE_FAILED = 4
} bfm_state;

typedef enum {
	BFM_RESET_NORMAL = 0,
	BFM_RESET_SPECIAL = 1   /* BREAK付き特殊リセット */
} bfm_reset_kind;

typedef enum {
	BFM_CMD_RESET = 0,
	BFM_CMD_SPECIAL_RESET = 1,
	/* 以降はspike専用。製品APIには持ち込まない。 */
	BFM_CMD_SPIKE_STALL = 100,  /* Core threadを arg ミリ秒だけ滞留させる */
	BFM_CMD_SPIKE_THROW = 101   /* Core thread内で例外を送出する */
} bfm_command_kind;

typedef struct {
	uint32_t kind;   /* bfm_command_kind */
	int64_t arg;
} bfm_command;

typedef enum {
	BFM_EVENT_LIFECYCLE_CHANGED = 0,
	BFM_EVENT_COMMAND_COMPLETED = 1,
	BFM_EVENT_ERROR = 2
} bfm_event_kind;

typedef struct {
	uint32_t kind;         /* bfm_event_kind */
	uint64_t command_id;   /* COMMAND_COMPLETED のとき、対応するコマンドの連番 */
	int32_t state;         /* LIFECYCLE_CHANGED のとき、bfm_state */
	int32_t code;          /* ERROR のとき、bfm_result */
} bfm_event;

typedef struct {
	/* コアがアプリケーションデータを置く位置。ホストが必ず決める。 */
	const char* home_dir;
	/* コマンドキューとイベントキューの上限。0なら既定値。 */
	uint32_t command_queue_capacity;
	uint32_t event_queue_capacity;
} bfm_create_options;

/* 生成側が bfm_destroy で解放する。out は成功時のみ書き換える。 */
bfm_result bfm_create(const bfm_create_options* options, bfm_session** out);
void bfm_destroy(bfm_session* session);

bfm_result bfm_start(bfm_session* session);
bfm_result bfm_stop(bfm_session* session);
bfm_result bfm_reset(bfm_session* session, bfm_reset_kind kind, uint64_t* out_command_id);

/* 投入したコマンドの連番を out_command_id へ返す。完了は同じIDのイベントで通知する。 */
bfm_result bfm_send_command(bfm_session* session, const bfm_command* command,
                            uint64_t* out_command_id);

/* イベントが無ければ BFM_ERR_NO_EVENT を返す。ポインタは呼び出し側の所有。 */
bfm_result bfm_poll_event(bfm_session* session, bfm_event* out);

bfm_state bfm_get_state(bfm_session* session);

/* 検証用の統計。 */
typedef struct {
	uint64_t frames_run;
	uint64_t commands_accepted;
	uint64_t commands_rejected;   /* キュー飽和で拒否した数 */
	uint64_t events_dropped;      /* UI停止で捨てた古いイベント数 */
} bfm_stats;

bfm_result bfm_get_stats(bfm_session* session, bfm_stats* out);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* BFM_SESSION_SPIKE_H_ */
