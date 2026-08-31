/*
 * CocoaPodsは1つ以上のソースファイルを要求するため置く空実装。
 *
 * 実際のネイティブコードは native/CMakeLists.txt がビルドし、
 * podspec の script_phase が作る libbubi_fm77av40ex_core_plugin.a に入る。
 * ここへ実装を足さない。
 */
void bubi_fm77av40ex_core_placeholder(void) {}
