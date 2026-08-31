/*
 * BubiFM77AV40EX 製品用 C ABI（design.md 4.1〜4.3、development_plan.md 6 WP1）。
 *
 * 方針は design.md 16.1「C ABIとCore thread」の決定記録に従う。
 *   - 不透明ハンドルのみを公開する。C++型をDartへ露出しない。
 *   - 固定幅整数、POD構造体、列挙されたエラーコードだけを使う。
 *   - C境界を跨ぐメモリは確保側が解放する。
 *   - 例外を境界外へ送出しない。
 *   - VMの生成・操作・破棄はすべてCore threadに閉じる。
 *
 * 型空間（コマンド種別・イベント種別・エラー）はWP1で design.md 4.2/4.3 の
 * 分類を網羅して定義する。実装はWP1の範囲（ライフサイクルとリセット）に限り、
 * 未実装の種別は BFM_ERR_UNSUPPORTED を返す。呼び出し側の誤りを表す
 * BFM_ERR_INVALID_ARGUMENT とは区別する。
 */
#ifndef BUBI_FM77AV_H_
#define BUBI_FM77AV_H_

#include <stdint.h>

/*
 * 静的ライブラリをアプリへ -force_load する構成のため、既定の
 * hidden visibility とReleaseのstripの両方から公開シンボルを守る。
 * 片方だけでは Release ビルドで dart:ffi の lookup が失敗する。
 */
#if defined(_WIN32)
#  define BFM_API __declspec(dllexport)
#else
#  define BFM_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* 不透明ハンドル。実体は公開しない。 */
typedef struct bfm_session bfm_session;

typedef enum {
	BFM_OK = 0,
	BFM_ERR_INVALID_ARGUMENT = 1, /* 呼び出し側の誤り（NULL、範囲外など） */
	BFM_ERR_INVALID_STATE = 2,    /* 二重開始、停止中の操作など */
	BFM_ERR_QUEUE_FULL = 3,       /* コマンドキューが上限に達した */
	BFM_ERR_NO_EVENT = 4,         /* poll時にイベントがない */
	BFM_ERR_CORE_FAILED = 5,      /* Core thread内で異常が発生した */
	BFM_ERR_UNSUPPORTED = 6,      /* 型としては定義済みだが未実装 */
	BFM_ERR_INTERNAL = 7          /* 境界で捕捉した想定外の例外 */
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
	BFM_RESET_SPECIAL = 1 /* BREAK付き特殊リセット */
} bfm_reset_kind;

/*
 * コマンド種別。design.md 4.2 の6分類を上位バイトで区切る。
 * WP1で実装するのは 0x01xx のリセットだけであり、他は予約である。
 * 予約値は enum として存在するが bfm_send_command は BFM_ERR_UNSUPPORTED を
 * 返す。実装するWPを各行に記す。
 */
typedef enum {
	/* ライフサイクル。start/stop は専用関数を使う。 */
	BFM_CMD_RESET = 0x0100,                  /* WP1 */
	BFM_CMD_SPECIAL_RESET = 0x0101,          /* WP1 */

	/* 実行 */
	BFM_CMD_SET_SPEED_MULTIPLIER = 0x0200,   /* M3 SYS-05 */
	BFM_CMD_SET_FULL_SPEED = 0x0201,         /* M3 SYS-06 */
	BFM_CMD_SET_BOOT_MODE = 0x0202,          /* WP2 SYS-04 */
	BFM_CMD_SET_CPU_TYPE = 0x0203,           /* M3 SYS-03 */

	/* 媒体 */
	BFM_CMD_INSERT_FDD = 0x0300,             /* WP5 FDD-01 */
	BFM_CMD_EJECT_FDD = 0x0301,              /* WP5 FDD-01 */
	BFM_CMD_SET_FDD_WRITE_PROTECT = 0x0302,  /* M3 FDD-03 */
	BFM_CMD_SET_FDD_TIMING = 0x0303,         /* M3 FDD-05 */
	BFM_CMD_SET_FDD_CRC_CHECK = 0x0304,      /* M3 FDD-06 */
	BFM_CMD_INSERT_CMT = 0x0310,             /* M7 P2 */
	BFM_CMD_EJECT_CMT = 0x0311,              /* M7 P2 */
	BFM_CMD_CONTROL_CMT = 0x0312,            /* M7 P2 */

	/* 入力 */
	BFM_CMD_KEY_DOWN = 0x0400,               /* WP3 INP-01 */
	BFM_CMD_KEY_UP = 0x0401,                 /* WP3 INP-01 */
	BFM_CMD_MOUSE = 0x0402,                  /* M7 P2 */
	BFM_CMD_JOYSTICK = 0x0403,               /* M3 INP-03 */
	BFM_CMD_AUTO_KEY = 0x0404,               /* M3 INP-05 */

	/* 構成 */
	BFM_CMD_SET_SOUND_TYPE = 0x0500,         /* M3 AUD-03 */
	BFM_CMD_SET_OPTION_SWITCH = 0x0501,      /* M3 SYS-03 */
	BFM_CMD_SET_VOLUME = 0x0502,             /* M3 AUD-05 */
	BFM_CMD_SET_FRAME_RATE = 0x0503,         /* M3 VID-05 */

	/* 状態 */
	BFM_CMD_SAVE_STATE = 0x0600,             /* M3 STA-01 */
	BFM_CMD_LOAD_STATE = 0x0601,             /* M3 STA-02 */

	/* デバッグ */
	BFM_CMD_DEBUGGER_OPEN = 0x0700,          /* M7 DBG-01 */
	BFM_CMD_DEBUGGER_CLOSE = 0x0701,         /* M7 DBG-01 */
	BFM_CMD_DEBUGGER_EXECUTE = 0x0702        /* M7 DBG-02 */
} bfm_command_kind;

typedef struct {
	uint32_t kind;    /* bfm_command_kind */
	int32_t reserved; /* 0を入れる。構造体の詰め物を明示する。 */
	int64_t arg0;
	int64_t arg1;
	/*
	 * ファイルパス等。呼び出し中だけ借用し、実装側が複製する。
	 * 関数から戻った後の寿命は呼び出し側が自由に決めてよい。
	 */
	const char* text;
} bfm_command;

/* design.md 4.3 の低頻度イベント。高頻度データはここを通さない。 */
typedef enum {
	BFM_EVENT_LIFECYCLE_CHANGED = 0,   /* WP1 */
	BFM_EVENT_COMMAND_COMPLETED = 1,   /* WP1 */
	BFM_EVENT_ERROR = 2,               /* WP1 */
	BFM_EVENT_MEDIA_CHANGED = 3,       /* WP5 */
	BFM_EVENT_MEDIA_ACCESS_CHANGED = 4,/* WP5 */
	BFM_EVENT_TAPE_POSITION_CHANGED = 5,/* M7 P2 */
	BFM_EVENT_FDD_MECHANICAL = 6,      /* M3 AUD-04 */
	BFM_EVENT_LED_CHANGED = 7,         /* WP6 */
	BFM_EVENT_SCREEN_MODE_CHANGED = 8, /* WP3 */
	BFM_EVENT_PERFORMANCE_CHANGED = 9, /* WP6 */
	BFM_EVENT_STATE_SLOT_CHANGED = 10, /* M3 STA-01 */
	BFM_EVENT_DEBUGGER_STOPPED = 11    /* M7 DBG-02 */
} bfm_event_kind;

typedef struct {
	uint32_t kind;       /* bfm_event_kind */
	int32_t code;        /* ERROR のとき bfm_result、COMMAND_COMPLETED のとき結果 */
	uint64_t command_id; /* COMMAND_COMPLETED のとき、対応するコマンドの連番 */
	int64_t arg0;        /* LIFECYCLE_CHANGED のとき bfm_state */
	int64_t arg1;
} bfm_event;

typedef struct {
	/*
	 * コアがアプリケーションデータを置く位置。ホストが必ず決める。
	 * 空文字やNULLは受け付けない。upstreamの既定に委ねると
	 * ~/CommonSourceCodeProject/ を作ってしまい design.md 11.3 と食い違う。
	 */
	const char* home_dir;
	/* キュー上限。0なら既定値（コマンド64、イベント256）。 */
	uint32_t command_queue_capacity;
	uint32_t event_queue_capacity;
} bfm_create_options;

/* 確保側が bfm_destroy で解放する。out は成功時だけ書き換える。 */
BFM_API bfm_result bfm_create(const bfm_create_options* options, bfm_session** out);
/* NULL可。二重破棄以外は冪等。 */
BFM_API void bfm_destroy(bfm_session* session);

BFM_API bfm_result bfm_start(bfm_session* session);
/* 冪等。停止済みでも BFM_OK を返す。 */
BFM_API bfm_result bfm_stop(bfm_session* session);

/* 投入した連番を out_command_id へ返す。完了は同じIDのイベントで通知する。 */
BFM_API bfm_result bfm_reset(bfm_session* session, bfm_reset_kind kind,
                             uint64_t* out_command_id);
BFM_API bfm_result bfm_send_command(bfm_session* session, const bfm_command* command,
                                    uint64_t* out_command_id);

/* イベントが無ければ BFM_ERR_NO_EVENT を返す。out は呼び出し側の所有。 */
BFM_API bfm_result bfm_poll_event(bfm_session* session, bfm_event* out);

BFM_API int32_t bfm_get_state(bfm_session* session);

typedef struct {
	uint64_t frames_run;
	uint64_t commands_accepted;
	uint64_t commands_rejected; /* キュー飽和で拒否した数 */
	uint64_t events_dropped;    /* UI遅延で捨てた古いイベント数 */
	/*
	 * Core thread以外からVM操作境界へ入った回数。
	 * 正常動作では常に0でなければならない（development_plan.md 6 WP1
	 * 「Core threadだけがVMを操作することをテストする」）。
	 */
	uint64_t vm_access_violations;
} bfm_stats;

BFM_API bfm_result bfm_get_stats(bfm_session* session, bfm_stats* out);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* BUBI_FM77AV_H_ */
