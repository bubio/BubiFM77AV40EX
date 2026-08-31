/*
 * mc6809.cpp / mc6809_base.cpp / hd6844.cpp 専用のシム
 * （この3ファイルにだけ -include する）。
 *
 * upstream のこれらは _MSC_VER 以外の経路で、DEVICE が持たない `osd` を通じて
 * 機能問合せとデバッガー停止待ちを行う。他のCPU実装はいずれも `emu->` を
 * 使っており、この3ファイルだけの不整合である。
 *
 * コアを1行も変更しない方針のため、当該ファイルに限りグローバルの
 * 問合せ先を供給する。`check_feature` は upstream の _MSC_VER 側の分岐と
 * 同じ結果（コンパイル時の機種定義に基づく値）を返し、Windowsビルドと
 * 挙動を一致させる。停止待ちはM0〜M1でデバッガーを開かないため何もしない。
 * デバッガー本体はP2（DBG-01/DBG-02）で改めて技術検証する。
 */
#ifndef BUBI_CORE_FEATURE_SHIM_H_
#define BUBI_CORE_FEATURE_SHIM_H_

struct BubiCoreFeatureShim {
	// upstream の _MSC_VER 分岐と同じ値を返す。実装は core_feature_shim.cpp。
	bool check_feature(const char* name);

	void start_waiting_in_debugger() {}
	void finish_waiting_in_debugger() {}
	void process_waiting_in_debugger() {}
};

// グローバル。EMU/OSD のメンバー `osd` は名前解決で常に優先されるため、
// `osd` を持たないこの3ファイルの翻訳単位だけがこれを参照する。
extern BubiCoreFeatureShim* osd;

#endif // BUBI_CORE_FEATURE_SHIM_H_
