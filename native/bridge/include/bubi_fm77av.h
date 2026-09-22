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
	BFM_ERR_INTERNAL = 7,         /* 境界で捕捉した想定外の例外 */
	/*
	 * rawイメージのサイズがFM7系の2D/2DDジオメトリのどちらとも一致しない、
	 * または変換形式（TD0/IMD/DSK/NFD/FDI）の変換後media_typeが2D/2DD以外
	 * だった（M3 FDD-03）。design.md 9.1「raw変換は容量だけで汎用geometry
	 * 表へフォールスルーさせない」を満たすための専用コード。
	 */
	BFM_ERR_UNSUPPORTED_GEOMETRY = 8,
	/*
	 * BFM_CMD_LOAD_STATE: 読込み対象ファイルの先頭4バイト（コアの
	 * STATE_VERSION、emu.cpp内`#define`）がブリッジの既知値と一致しない、
	 * またはファイルが読めない（M3 STA-02）。コア内部の
	 * EMU::load_state_tmpはこれより深いデバイス単位の不一致も検出して
	 * 現在の実行状態へロールバックするが、その結果はvoid APIからは
	 * 見えないため、ここで検出できるのは先頭バージョンチェックの範囲に限る
	 * （design.md「状態保存（M3、STA-01/STA-02）の実装方式」参照）。
	 */
	BFM_ERR_STATE_INCOMPATIBLE = 9
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
 * ブートモード（specification.md SYS-04）。値はupstreamの
 * config.boot_mode と同じで、コアはリセット時にこれを読む。
 */
typedef enum {
	BFM_BOOT_BASIC = 0,
	BFM_BOOT_DOS = 1
} bfm_boot_mode;

/*
 * Host > Sound の「オーディオバッファ」設定（design.md 7）。値は
 * upstreamの sound_latency_table（emu.cpp）先頭4エントリの添字と同じ
 * （[4]=400msは選択肢として出さない）。セッション生成後は変更できない。
 * EMU::EMU()がconfig.sound_latencyを起動時に1度だけ読むため、変更するには
 * セッションを作り直す必要がある。
 */
typedef enum {
	BFM_AUDIO_LATENCY_50MS = 0,
	BFM_AUDIO_LATENCY_100MS = 1,
	BFM_AUDIO_LATENCY_200MS = 2,
	BFM_AUDIO_LATENCY_300MS = 3
} bfm_audio_latency;

/*
 * CPU種別（specification.md SYS-05）。値はupstreamの config.cpu_type と
 * 同じ。BFM_CMD_SET_CPU_TYPE はコアの update_config() を呼ぶため、
 * リセットを待たずに反映される（design.md 16.1「実行設定の即時反映と
 * 拡張RAMの例外」）。
 */
typedef enum {
	BFM_CPU_FAST = 0, /* 2.0MHz相当 */
	BFM_CPU_SLOW = 1  /* 1.2MHz */
} bfm_cpu_type;

/*
 * 空ディスク作成の媒体種別（specification.md FDD-05）。値はupstreamの
 * MEDIA_TYPE_2D/MEDIA_TYPE_2DD（vm/disk.h）と同じ意味。
 */
typedef enum {
	BFM_FDD_MEDIA_2D = 0,
	BFM_FDD_MEDIA_2DD = 1
} bfm_fdd_media_type;

/*
 * BFM_CMD_SET_SOUND_VOLUME の arg0 に渡す論理チャンネル
 * （specification.md AUD-03）。VMのチャンネル番号（upstream
 * VM::set_sound_device_volume の引数）へは design.md「標準音声設定
 * （M3、AUD-03）の実装方式」に記録した対応表で変換する。OPN1/OPN2
 * （WHG/THG拡張、AUD-02、P2）とCMT関連チャンネルはここに含めない。
 */
typedef enum {
	BFM_SOUND_CHANNEL_OPN_FM = 0,
	BFM_SOUND_CHANNEL_OPN_PSG = 1,
	BFM_SOUND_CHANNEL_BEEP = 2,
	BFM_SOUND_CHANNEL_KEYBOARD_BEEP = 3,
	BFM_SOUND_CHANNEL_FDD_MECHANISM = 4
} bfm_sound_channel;

/*
 * BFM_CMD_CONTROL_CMT の arg0 に渡す操作種別（specification.md CMT-03、
 * M4）。原作Windows版のメニュー（native/core/upstream/src/res/
 * fm77av40ex.rc の"Play Button"/"Stop Button"/"Fast Forward"/
 * "Fast Rewind"、ID_PLAY_BUTTON1等）に対応するupstream
 * VM::push_play/push_stop/push_fast_forward/push_fast_rewindだけを使う。
 * APSS（push_apss_forward/push_apss_rewind、DATAREC::do_apss）は同じ.rcで
 * ID_APSS_FORWARD1/ID_APSS_REWIND1が予約されているだけで実際のメニューには
 * 配線されておらず、FM77AV40EXでは使われていない機能のためここに含めない。
 */
typedef enum {
	BFM_CMT_CONTROL_PLAY = 0,
	BFM_CMT_CONTROL_STOP = 1,
	BFM_CMT_CONTROL_FAST_FORWARD = 2,
	BFM_CMT_CONTROL_FAST_REWIND = 3
} bfm_cmt_control_op;

/*
 * BFM_CMD_SET_CMT_SOUND_ENABLE / BFM_CMD_SET_CMT_SOUND_VOLUME の arg0
 * （specification.md AUD-07）。原作の"Play CMT Noise"/"Play CMT Signal"/
 * "Play CMT Voice"（fm77av40ex.rc、ID_VM_SOUND_NOISE_CMT等）に対応する。
 * BFM_CMT_SOUND_VOICEはBFM_CMD_SET_CMT_SOUND_VOLUMEには渡せない
 * （下記コメント参照、BFM_ERR_INVALID_ARGUMENTを返す）。
 */
typedef enum {
	BFM_CMT_SOUND_NOISE = 0,
	BFM_CMT_SOUND_SIGNAL = 1,
	BFM_CMT_SOUND_VOICE = 2
} bfm_cmt_sound_kind;

/* BFM_CMD_SET_SCREEN_FILTER の arg0（VID-04）。 */
typedef enum {
	BFM_SCREEN_FILTER_NONE = 0,
	BFM_SCREEN_FILTER_RGB = 1
} bfm_screen_filter;

/*
 * BFM_CMD_SET_OPTION_SWITCH の arg0 に渡すビット（specification.md
 * SYS-06）。この3ビットの組だけを毎回丸ごと置き換える（マージしない）。
 * サイクルスチールとHSYNC同期はコアの update_config() で即時反映されるが、
 * 拡張RAMはコアがリセット時にしか読まないため、次のリセットまで見た目に
 * 反映されない（design.md 16.1）。arg0 にこの3ビット以外が立っていたら
 * BFM_ERR_INVALID_ARGUMENT を返す。
 */
enum {
	BFM_OPTSW_CYCLE_STEAL = 0x1,
	BFM_OPTSW_EXTENDED_RAM = 0x2,
	BFM_OPTSW_SYNC_TO_HSYNC = 0x4
};

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

	/*
	 * 実行。
	 *
	 * BFM_CMD_SET_SPEED_MULTIPLIER: arg0 は速度倍率の指数（0=x1、1=x2、
	 * 2=x4、3=x8、4=x16）。upstreamの config.cpu_power と同じ範囲で、
	 * ここへ直接書いて vm->update_config() を呼ぶ。Core threadが
	 * `vm->run()`を呼ぶ間隔（壁時計、frame_period）自体は変えない。
	 * `config.cpu_power`は1回のdrive()内で消費できるCPUクロック予算を
	 * `2^arg0`倍にする（`vm/event.cpp`のEVENT::drive()）。VSYNC等の
	 * イベントスケジューリングは「1 drive() = 1フレーム分のevent-clock」
	 * という固定単位で進むため、drive()の呼出し間隔・音声の生成ペースは
	 * 変わらない。一方、ホストCPUは1フレーム分のevent-clockを進める間に
	 * `2^arg0`倍のゲスト側CPU命令を実行できるため、VSYNC割込み待ちに
	 * 縛られないCPU律速の処理（BASICの実行速度、ディスクI/O待ちの
	 * ビジーループなど）は実際に速くなる（design.md 16.1「CPU速度倍率の
	 * 仕様」、利用者確認済み）。即時に反映される。範囲外は
	 * BFM_ERR_INVALID_ARGUMENT。
	 *
	 * BFM_CMD_SET_FULL_SPEED: 無制限速度（SYS-03の「無制限」）。arg0は
	 * 0または1（それ以外はBFM_ERR_INVALID_ARGUMENT）。1の間、Core thread
	 * は壁時計の待機を省き、`vm->run()`を間を置かず呼び続ける。
	 * `vm->run()`の呼出し間隔自体（＝VSYNC等のevent-clockスケジューリング
	 * と音声の生成ペース）が実時間より速くなるため、音声は生成量が
	 * 実時間48kHzの消費量を上回り、有界リングのオーバーラン方針
	 * （最古破棄）により再生が途切れがちになる（利用者確認済み。
	 * design.md 16.1「Full Speedの仕様」）。速度倍率（arg0の大小）が
	 * 高いほど、1回のdrive()あたりの実効CPU処理量が増えるため、Full
	 * Speedと組み合わせた実効速度も速くなる。
	 *
	 * BFM_CMD_SET_CPU_TYPE: arg0 は bfm_cpu_type。update_config() 経由で
	 * 即時反映される。
	 */
	BFM_CMD_SET_SPEED_MULTIPLIER = 0x0200,   /* M3 SYS-03 */
	BFM_CMD_SET_FULL_SPEED = 0x0201,         /* M3 SYS-03（無制限） */
	BFM_CMD_SET_BOOT_MODE = 0x0202,          /* WP2 SYS-04。arg0 は bfm_boot_mode */
	BFM_CMD_SET_CPU_TYPE = 0x0203,           /* M3 SYS-05 */

	/*
	 * 媒体。
	 *
	 * BFM_CMD_INSERT_FDD: arg0 はドライブ番号（0=FD1、1=FD2）、
	 * arg1 はD88バンク番号（0始まり）、text は開くファイルの絶対パス。
	 * design.md 9.1のとおりD88/D77/D8E/1DDだけを対象とし、呼び出し側
	 * （platform層）が書き戻し用の作業コピーを用意してから渡す。
	 * 対象ドライブに既に挿入済みなら BFM_ERR_INVALID_STATE を返す
	 * （先に BFM_CMD_EJECT_FDD で排出させる）。コアが受理しなかった
	 * 場合（不正な形式など）は BFM_ERR_INVALID_ARGUMENT を返す。
	 *
	 * BFM_CMD_EJECT_FDD: arg0 はドライブ番号。未挿入なら何もせず
	 * BFM_OK を返す（冪等）。挿入中ならコアがそのドライブへ書き戻して
	 * から排出する。呼び出し側は、この完了イベントを受けてから
	 * 作業コピーを原本へ原子的に反映すること。
	 *
	 * BFM_CMD_INSERT_FDD が受理する形式（specification.md FDD-02/FDD-03）:
	 * D88/D77/D8E/1DDはそのままコアへ渡す。拡張子がTD0/IMD/DSK/NFD/FDIの
	 * 場合はコアが変換してから開き、変換後のmedia_typeが2D/2DD以外なら
	 * BFM_ERR_UNSUPPORTED_GEOMETRY で拒否して即座に排出する。それ以外の
	 * 拡張子（raw扱い）はコアへ渡す前にブリッジがファイルサイズを直接
	 * 確認し、327,680（2D）または655,360（2DD）バイトのどちらでもなければ
	 * コアを呼ばずに BFM_ERR_UNSUPPORTED_GEOMETRY で拒否する
	 * （design.md 9.1「raw変換は容量だけで汎用geometry表へフォールスルー
	 * させない」）。
	 *
	 * BFM_CMD_INSERT_FDD の arg1（D88バンク番号）は同一ファイル内の
	 * バンク切替にも使う。バンク数と現在のバンクは bfm_get_fdd_bank_info
	 * で取得できる（M3 FDD-04）。
	 */
	BFM_CMD_INSERT_FDD = 0x0300,             /* WP5 FDD-01、M3 FDD-03/FDD-04 */
	BFM_CMD_EJECT_FDD = 0x0301,              /* WP5 FDD-01 */
	/*
	 * BFM_CMD_SET_FDD_WRITE_PROTECT / _TIMING / _CRC_CHECK
	 * （specification.md FDD-06、ドライブごとの書込み保護・タイミング
	 * 補正・CRCエラー無視）。arg0 はドライブ番号、arg1 は0/1
	 * （それ以外は BFM_ERR_INVALID_ARGUMENT）。
	 *
	 * WRITE_PROTECT は upstream の EMU::is_floppy_disk_protected(drv, value)
	 * を呼ぶ、ディスク単位のランタイム状態。未挿入でも設定でき、次に
	 * 挿入されたディスクへそのまま適用される。
	 *
	 * TIMING / CRC_CHECK は upstream の config.correct_disk_timing[drv] /
	 * config.ignore_disk_crc[drv]（drive_num添字の配列）へ直接書く。
	 * どちらもDISK側が呼出しのたびに読むため、update_config() は不要で
	 * 即時反映される。
	 */
	BFM_CMD_SET_FDD_WRITE_PROTECT = 0x0302,  /* M3 FDD-06 */
	BFM_CMD_SET_FDD_TIMING = 0x0303,         /* M3 FDD-06 */
	BFM_CMD_SET_FDD_CRC_CHECK = 0x0304,      /* M3 FDD-06 */
	/*
	 * BFM_CMD_CREATE_BLANK_FDD: 空の2D/2DDディスクイメージを作る
	 * （specification.md FDD-05）。arg0 は bfm_fdd_media_type、text は
	 * 作成先の絶対パス。upstream の EMU::create_blank_floppy_disk() を
	 * 一時ファイルへ書いてから同一ボリュームで原子的に rename する
	 * （design.md 9「空ディスク作成は一時ファイルへ完全に書き、同一
	 * ボリューム上で置換する」）。ドライブへの挿入は別途
	 * BFM_CMD_INSERT_FDD で行う（このコマンド自体は挿入しない）。
	 */
	BFM_CMD_CREATE_BLANK_FDD = 0x0305,       /* M3 FDD-05 */
	/*
	 * BFM_CMD_INSERT_CMT: arg0 は0（再生用に開く、CMT-01）または1（録音用に
	 * 新規作成、CMT-02）、text はコアがそのまま開く絶対パス（拡張子
	 * .t77/.wav/.tapでコアが自動判別する、upstream
	 * DATAREC::play_tape/rec_tapeのcheck_file_extension）。design.md 9.1の
	 * FDDと同じ境界（呼び出し側が作業コピーを用意する）を使うが、録音は
	 * upstreamが FILEIO_READ_WRITE_NEW_BINARY で新規作成するため、既存
	 * ファイルの有無を問わない。既に挿入済みなら BFM_ERR_INVALID_STATE
	 * （先に BFM_CMD_EJECT_CMT で排出させる）。コアが受理しなかった場合は
	 * BFM_ERR_INVALID_ARGUMENT。
	 *
	 * BFM_CMD_EJECT_CMT: arg0/arg1/textともに未使用。未挿入なら何もせず
	 * BFM_OK（FDDと同じ冪等方針）。
	 *
	 * BFM_CMD_CONTROL_CMT: arg0 は bfm_cmt_control_op。原作の"Play Button"/
	 * "Stop Button"/"Fast Forward"/"Fast Rewind"に対応する
	 * upstream VM::push_play/push_stop/push_fast_forward/push_fast_rewindを
	 * 呼ぶ（bfm_cmt_control_op前掲コメントのとおりAPSSは対象外）。
	 */
	BFM_CMD_INSERT_CMT = 0x0310,             /* M4 CMT-01/CMT-02 */
	BFM_CMD_EJECT_CMT = 0x0311,              /* M4 CMT-01 */
	BFM_CMD_CONTROL_CMT = 0x0312,            /* M4 CMT-03 */
	/*
	 * BFM_CMD_SET_CMT_WAVE_SHAPING: arg0 は0/1（CMT-04）。upstreamの
	 * config.wave_shaper[0]へ直接書く。DATAREC::load_wav_image()が
	 * 呼出しのたびに直接読むため、FDDのTIMING/CRC_CHECKと同じく
	 * update_config()は不要（design.md 16.1と同じ方針）。
	 */
	BFM_CMD_SET_CMT_WAVE_SHAPING = 0x0313,   /* M4 CMT-04 */
	/*
	 * BFM_CMD_SET_CMT_SOUND_ENABLE: arg0 は bfm_cmt_sound_kind、arg1 は
	 * 0/1（AUD-07の有効・無効）。upstreamの
	 * config.sound_noise_cmt/sound_tape_signal/sound_tape_voiceへ書き、
	 * vm->update_config()を呼ぶ（DATAREC::update_config()が
	 * sound_noise_cmtを読んでNOISEのmuteを更新するため必須。design.md
	 * 16.1「実行設定の即時反映」と同じ方針）。
	 */
	BFM_CMD_SET_CMT_SOUND_ENABLE = 0x0314,   /* M4 AUD-07 */
	/*
	 * BFM_CMD_SET_CMT_SOUND_VOLUME: arg0 は bfm_cmt_sound_kind
	 * （BFM_CMT_SOUND_VOICEは対象外、BFM_ERR_INVALID_ARGUMENT）、arg1は
	 * デシベル（AUD-03と同じ0.5dB刻み、[-192, 0]の範囲外は
	 * BFM_ERR_INVALID_ARGUMENT）。upstream
	 * VM::set_sound_device_volume(ch, ...)（native/core/upstream/src/vm/
	 * fm7/fm7.cpp:860-915）のch7がCMT信号（DATAREC::set_volume(0,...)）、
	 * ch10がCMTノイズ（drec->get_context_noise_play/stop/fast）に対応する。
	 * ch7はDATAREC::set_volume(1,...)（CMT音声）へは到達しないため、
	 * CMT音声の音量は調整できない（upstream改変禁止のための既知の制約、
	 * design.md「標準音声設定（M3、AUD-03）の実装方式」隣接の注記参照）。
	 */
	BFM_CMD_SET_CMT_SOUND_VOLUME = 0x0315,   /* M4 AUD-07 */
	/*
	 * BFM_CMD_SET_CMT_FAST_LOAD: arg0 は0/1（CMT-06）。1の間、テープの
	 * モーターが回っている再生中（DATAREC::is_tape_playing()、
	 * remote && play）だけCore threadが壁時計の待機を省き、Full Speedと
	 * 同じくVMを無制限速度で進める。加速中に生成した音声はリングへ積まずに
	 * 捨てる。録音中は加速しない。upstreamのconfigには対応する項目がなく、
	 * bridge側だけの設定。セッション生成時の既定は1。
	 */
	BFM_CMD_SET_CMT_FAST_LOAD = 0x0316,      /* CMT-06 */

	/* 入力 */
	BFM_CMD_KEY_DOWN = 0x0400,               /* WP3 INP-01 */
	BFM_CMD_KEY_UP = 0x0401,                 /* WP3 INP-01 */
	BFM_CMD_MOUSE = 0x0402,                  /* M7 P2 */
	/*
	 * BFM_CMD_JOYSTICK: 予約のみ・未使用（列挙値の後方互換のため残す）。
	 * ジョイスティックの直接入力は高頻度の連続状態であり、キーボードのような
	 * 離散イベントのキュー経由コマンドという性質と合わないため、実際の
	 * 実装は bfm_set_joystick_state（直接関数、M3 INP-04）で行う
	 * （design.md 8「固定長スナップショット領域」の方針）。
	 */
	BFM_CMD_JOYSTICK = 0x0403,               /* 予約・未使用 */
	BFM_CMD_AUTO_KEY = 0x0404,               /* M3 INP-05 */

	/* 構成 */
	/*
	 * BFM_CMD_SET_OPTION_SWITCH: arg0 は BFM_OPTSW_* の組合せ
	 * （bubi_fm77av.h 前掲）。サイクルスチール／HSYNC同期は即時、
	 * 拡張RAMは次のリセットまで反映されない（design.md 16.1）。
	 */
	BFM_CMD_SET_SOUND_TYPE = 0x0500,         /* M3 AUD-02（P2、未実装） */
	BFM_CMD_SET_OPTION_SWITCH = 0x0501,      /* M3 SYS-06 */
	BFM_CMD_SET_VOLUME = 0x0502,             /* M3 AUD-05 */
	BFM_CMD_SET_FRAME_RATE = 0x0503,         /* M3 VID-05 */
	/*
	 * BFM_CMD_SET_SOUND_VOLUME: 標準OPNのFM・PSG、Beep、キーボード音、
	 * FDD機構音の音量を個別に調整する（specification.md AUD-03）。
	 * arg0 は bfm_sound_channel、arg1 はデシベル（0.5dB刻み、0=最大、
	 * [-192, 0]の範囲外は BFM_ERR_INVALID_ARGUMENT）。L/Rは同値で送る
	 * （このAPIにステレオ定位の要求はない）。
	 *
	 * upstream の VM::set_sound_device_volume(ch, decibel_l, decibel_r)
	 * （native/core/upstream/src/vm/fm7/fm7.cpp）を
	 * EMU::set_sound_device_volume() 経由で直接呼ぶ。design.md
	 * 「標準音声設定（M3、AUD-03）の実装方式」に論理チャンネルと
	 * VMチャンネル番号の対応表を記録する。
	 */
	BFM_CMD_SET_SOUND_VOLUME = 0x0504,       /* M3 AUD-03 */
	/*
	 * BFM_CMD_SET_SCREEN_FILTER: arg0 は bfm_screen_filter（VID-04）。
	 * upstream の config.filter_type に当たる。RGBの間、Core threadは
	 * コアの画面へ upstream と同じ apply_rgb_filter_to_screen_buffer を
	 * 掛け、コアの画面の BFM_CMD_SET_SCREEN_POWER 倍の面を公開する
	 * （bfm_video_frame の幅・高さはその大きさになる。
	 * BFM_EVENT_SCREEN_MODE_CHANGED はコアの画面の大きさのまま）。
	 * 範囲外は BFM_ERR_INVALID_ARGUMENT。
	 *
	 * BFM_CMD_SET_SCREEN_POWER: arg0 は横、arg1 は縦の倍率（1〜8）。
	 * upstream の draw_screen() が表示の大きさから求める tmp_pow_x/y
	 * （ceil(表示幅 / 画面幅)、ceil(表示高 / 画面高)）に当たり、表示側が
	 * 同じ式で求めて渡す。範囲外は BFM_ERR_INVALID_ARGUMENT。既定は1。
	 */
	BFM_CMD_SET_SCREEN_FILTER = 0x0505,      /* VID-04 */
	BFM_CMD_SET_SCREEN_POWER = 0x0506,       /* VID-04 */
	/*
	 * BFM_CMD_SET_FDD_NOISE_ENABLE: arg0 は0/1（AUD-04のシーク音・
	 * ヘッドロード／アンロード音）。upstreamのconfig.sound_noise_fddへ書き、
	 * vm->update_config()でMB8877::update_config()（NOISEのmute反映）まで
	 * 通す。素材WAVはブリッジが合成して置く（cmt_noise.h）。音量は
	 * BFM_CMD_SET_SOUND_VOLUMEのBFM_SOUND_CHANNEL_FDD_MECHANISM（VMのch9）。
	 * セッション生成時の既定は1。
	 */
	BFM_CMD_SET_FDD_NOISE_ENABLE = 0x0507,   /* AUD-04 */

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
	/*
	 * 予約のみで未使用。FD1/FD2アクセス状態はVM::is_floppy_disk_accessed()
	 * （MB8877::read_signal）自体が読むたびにフラグを消費するread-and-clear
	 * のため、イベント化すると実アクセス中は1フレームおきに立って落ちる
	 * 高頻度イベントになり、design.md 4.3が禁じる高頻度データをここへ
	 * 流してしまう。代わりに bfm_get_media_access のポーリングで読む。
	 */
	BFM_EVENT_MEDIA_ACCESS_CHANGED = 4,/* 未使用。bfm_get_media_access を使う */
	/*
	 * upstream DATAREC::get_message()（"Play"/"Stop (NN %)"/"Record"等、
	 * CMT-05）が返す状態文字列が前回と変わったときだけ発火する低頻度
	 * イベント（BFM_EVENT_LED_CHANGEDと同じ「変化検知してイベント化」
	 * 方針）。走行位置(%)自体は毎フレーム変わりうる高頻度データのため
	 * イベントには含めず、bfm_get_cmt_status のポーリング専用とする
	 * （design.md 4.3が禁じる高頻度データをここへ流さないため、
	 * BFM_EVENT_MEDIA_ACCESS_CHANGEDと同じ考え方）。
	 */
	BFM_EVENT_TAPE_POSITION_CHANGED = 5,/* M4 CMT-05 */
	BFM_EVENT_FDD_MECHANICAL = 6,      /* M3 AUD-04 */
	BFM_EVENT_LED_CHANGED = 7,         /* WP3 INP-02 */
	BFM_EVENT_SCREEN_MODE_CHANGED = 8, /* WP3 */
	BFM_EVENT_PERFORMANCE_CHANGED = 9, /* WP6 */
	BFM_EVENT_STATE_SLOT_CHANGED = 10, /* M3 STA-01 */
	BFM_EVENT_DEBUGGER_STOPPED = 11    /* M7 DBG-02 */
} bfm_event_kind;

typedef struct {
	uint32_t kind;       /* bfm_event_kind */
	int32_t code;        /* ERROR のとき bfm_result、COMMAND_COMPLETED のとき結果 */
	uint64_t command_id; /* COMMAND_COMPLETED のとき、対応するコマンドの連番 */
	int64_t arg0;        /* LIFECYCLE_CHANGED のとき bfm_state、
	                      * LED_CHANGED のとき0x1=INS/0x2=KANA/0x4=CAPSのビット合成、
	                      * MEDIA_CHANGED のときドライブ番号（0=FD1、1=FD2） */
	int64_t arg1;        /* MEDIA_CHANGED のとき1=挿入、0=排出 */
} bfm_event;

typedef struct {
	/*
	 * コアがアプリケーションデータを置く位置。ホストが必ず決める。
	 * 空文字やNULLは受け付けない。upstreamの既定に委ねると
	 * ~/CommonSourceCodeProject/ を作ってしまい design.md 11.3 と食い違う。
	 *
	 * upstreamの get_application_path() は初回呼出しで値を固定するため、
	 * この値はプロセス全体で1つに限る。2回目以降の bfm_create が違う値を
	 * 渡した場合は BFM_ERR_INVALID_STATE を返す。変更にはプロセス再起動が要る。
	 */
	const char* home_dir;

	/*
	 * 利用者が選んだROMディレクトリ。NULLまたは空なら結線しない。
	 *
	 * コアはROMを1つのディレクトリからしか読まないため、ブリッジが
	 * 作業ディレクトリを用意し、ここの各ファイルへシンボリックリンクを
	 * 張る。原本は複製せず元の位置に残す（design.md 16.1）。
	 * ROMの検証はホスト側の責務であり、ここでは行わない。
	 */
	const char* rom_dir;

	/* 起動時のブートモード（bfm_boot_mode）。既定は BFM_BOOT_BASIC。 */
	int32_t boot_mode;

	/* キュー上限。0なら既定値（コマンド64、イベント256）。 */
	uint32_t command_queue_capacity;
	uint32_t event_queue_capacity;

	/*
	 * オーディオバッファ（bfm_audio_latency）。既定は BFM_AUDIO_LATENCY_50MS
	 * （ゼロ初期化と一致）。範囲外の値は BFM_ERR_INVALID_ARGUMENT。
	 */
	int32_t audio_latency;
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

/*
 * コアが実際にROMを読み USERDIC.DAT を書くディレクトリを、終端NUL付きで
 * out へ書く。連結規則はupstreamの get_application_path() が決めるため、
 * ホスト側で組み立てず必ずここから得ること。
 * out_size が足りない場合は BFM_ERR_INVALID_ARGUMENT を返す。
 */
BFM_API bfm_result bfm_get_core_directory(bfm_session* session, char* out,
                                          uint32_t out_size);


/*
 * 映像（design.md 6、16.1「映像の受け渡しとmacOS Texture方式」）。
 *
 * コアのバッファは渡さない。解像度が変わるとコアが確保し直すため、
 * 渡したポインターがその瞬間に無効になる。ここで返すのはブリッジが
 * 所有する面であり、release するまで内容も大きさも変わらない。
 *
 * pixels は BGRA8888、上から下へ、幅×高さの連続領域である。
 * コアはアルファを書かないため、ブリッジが 0xff を埋めてある。
 * 埋めないと画面全体が背景と混ざる。
 */
typedef struct {
	const uint32_t* pixels;
	uint32_t width;
	uint32_t height;
	uint32_t reserved; /* 0。構造体の詰め物を明示する。 */
	uint64_t generation;
} bfm_video_frame;

/*
 * 最新の完成フレームを借りる。まだ1枚もなければ BFM_ERR_NO_EVENT を返す。
 * 借りたら必ず bfm_release_video_frame を同じ generation で呼ぶこと。
 * 返すまでその面は書き潰されない。
 *
 * どのスレッドから呼んでもよい。VMには触れない。
 * 呼び手を待たせないため、Core threadの複製が終わるのを待つことはない。
 */
BFM_API bfm_result bfm_acquire_video_frame(bfm_session* session,
                                           bfm_video_frame* out);

/* 借りた面を返す。未知の generation は黙って無視する。 */
BFM_API void bfm_release_video_frame(bfm_session* session, uint64_t generation);

/*
 * 最新の完成フレームの世代番号。まだ1枚もなければ0。
 * 借りずに「変わったかどうか」だけを知りたいときに使う。
 * 描画側はこれで変化を見てから転送すればよい（VID-07）。
 */
BFM_API uint64_t bfm_video_generation(bfm_session* session);

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
	/* 公開したフレーム数と、書ける面が尽きて捨てたフレーム数。 */
	uint64_t frames_published;
	uint64_t frames_dropped;
	/*
	 * 音声（design.md 7、16.1）。audio_frames_producedはCore threadが
	 * vm->create_sound()で取り出したフレーム数の累計。
	 * audio_underrun_framesはbfm_read_audioが無音で埋めたフレーム数、
	 * audio_overrun_framesは読み手が追いつかず最古から捨てたフレーム数の
	 * 累計。どちらも常時0とは限らないが、再生が追いついていれば
	 * 増加が緩やかに収まる。
	 */
	uint64_t audio_frames_produced;
	uint64_t audio_underrun_frames;
	uint64_t audio_overrun_frames;
} bfm_stats;

BFM_API bfm_result bfm_get_stats(bfm_session* session, bfm_stats* out);

/*
 * FD1/FD2アクセス状態（design.md WP5「アクセス状態」）。
 * ビット0=FD1、ビット1=FD2、アクセス（モーターオン相当）中なら1。
 *
 * upstreamのMB8877::read_signal()自体が読むたびにフラグを消費する
 * read-and-clearであり、Core threadが毎フレーム蓄積した値を、
 * この関数を呼んだ側が読むたびに0へ戻す。BFM_EVENT_MEDIA_ACCESS_CHANGED
 * イベントは使わない（bubi_fm77av.hの当該コメントを参照）。
 * 消費者は1つに保つこと。複数箇所から呼ぶと取り合いになる。
 */
BFM_API bfm_result bfm_get_media_access(bfm_session* session, uint32_t* out_bits);

/*
 * D88のバンク情報（design.md 「D88 bank list」、M3 FDD-04）。
 *
 * upstream の EMU::open_floppy_disk() が挿入時に file_bank/bank_num を
 * 数え上げて emu->d88_file[drv] へ保持する。この関数は挿入・排出の
 * 完了後にその値を読むだけで、Core threadの実行を待たせない。
 * out_bank_num は総バンク数（単一ディスクのD88なら1）、out_cur_bank は
 * 現在開いているバンク番号（0始まり）。未挿入なら両方0を返す。
 */
BFM_API bfm_result bfm_get_fdd_bank_info(bfm_session* session, int32_t drive,
                                         int32_t* out_bank_num,
                                         int32_t* out_cur_bank);

/*
 * ドライブごとの書込み保護の実際値（M3 FDD-06）。0または1をout_valueへ
 * 書く。upstreamの DISK::open() はディスク単位のwrite_protectedを
 * 呼出しのたびにまずfalseへ戻してから、開いたD88ファイル自身の
 * ヘッダprotectバイトを見て必要ならtrueへ立て直す（vm/disk.cpp）。
 * つまり挿入直後は「そのファイル自身が持つ書込み保護の有無」を返す。
 * BFM_CMD_SET_FDD_WRITE_PROTECTで明示的に変更した場合はその値を返す。
 * 未挿入なら0を返す。
 */
BFM_API bfm_result bfm_get_fdd_write_protect(bfm_session* session, int32_t drive,
                                             int32_t* out_value);

/*
 * CMTの現在状態（design.md「D88 bank list」と同型の直接アクセサ、
 * specification.md CMT-05、M4）。message は終端NULを含めて必ず
 * NUL終端し、収まらない場合は切り詰める。position は0〜100（未挿入または
 * 再生中でなければ0、upstream DATAREC::get_tape_position()と同じ意味）。
 * 未挿入なら inserted/playing/recording はすべて0、message は空文字。
 */
typedef struct {
	int32_t inserted;
	int32_t playing;
	int32_t recording;
	int32_t position;
	char message[128];
} bfm_cmt_status;

BFM_API bfm_result bfm_get_cmt_status(bfm_session* session, bfm_cmt_status* out);

/*
 * ジョイスティックの直接入力（design.md 8「固定長スナップショット領域」、
 * M3 INP-04）。どのスレッドからでも呼べる。index は 0=JS1、1=JS2
 * （それ以外は BFM_ERR_INVALID_ARGUMENT）。bits はビット0〜3が方向
 * （Up/Down/Left/Right）、ビット4〜5がボタン1・2、いずれも1が押下状態
 * （active-high、vm/fm7/joystick.cppの規約）。それ以外のビットは無視する
 * （下位6ビットへマスクする）。呼ぶたびに即座に複製を更新するだけで、
 * Core threadがフレームごとに最新値を読み出す（design.md 8）。
 */
BFM_API bfm_result bfm_set_joystick_state(bfm_session* session, int32_t index,
                                          uint32_t bits);

/*
 * 一時停止（ホスト側UIの都合によるポーズ）。どのスレッドからでも呼べる。
 * paused は0または1（それ以外は BFM_ERR_INVALID_ARGUMENT）。1の間、
 * Core threadは`vm->run()`を呼ばず、壁時計の1周期ごとにコマンドの取込み
 * だけを続ける（FDD挿入・状態保存などは一時停止中でも完了する）。ゲスト
 * 時間は進まず、音声は生成されないため再生側はアンダーランの無音埋めに
 * なる。Full Speedより優先する。呼ぶたびに即座に値を更新するだけで、
 * Core threadの起動前後どちらから呼んでも安全（値は次の起動にも残る）。
 */
BFM_API bfm_result bfm_set_paused(bfm_session* session, int32_t paused);

/*
 * 音声（design.md 7、16.1「音声はVMの駆動源にしない」）。
 *
 * コアのPCMをブリッジが所有する有界リングへ蓄え、ここから複製で渡す。
 * frame_capacity分を必ず埋めて返す。足りない分は無音で埋め、
 * bfm_stats.audio_underrun_framesを増やす。どのスレッドから呼んでもよい。
 * VMには触れない。
 */
BFM_API bfm_result bfm_read_audio(bfm_session* session, int16_t* out,
                                  uint32_t frame_capacity);

/*
 * 出力フォーマット（サンプルレート、チャネル数）。プロセス内で固定であり、
 * セッションの状態に関わらず得られる。
 */
BFM_API bfm_result bfm_get_audio_format(bfm_session* session,
                                        uint32_t* out_sample_rate,
                                        uint32_t* out_channels);

#ifdef __cplusplus
} /* extern "C" */
#endif

#endif /* BUBI_FM77AV_H_ */
