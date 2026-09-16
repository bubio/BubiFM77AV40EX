# Windows向けの薄いラッパー。実体は ../src/CMakeLists.txt が参照する
# native/CMakeLists.txt にある（design.md 16.1）。
#
# Flutterのツールが要求する形（PLUGIN_NAME の名前、apply_standard_settings、
# <project>_bundled_libraries）はプラグインテンプレートに合わせる。
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "bubifm77av40ex_core")
project(${PROJECT_NAME} LANGUAGES CXX C)

# この名前はFlutterのツールが生成するビルド定義から参照されるため変えない。
set(PLUGIN_NAME "bubifm77av40ex_core_plugin")

# コア（native/）ではランナーから継承した UNICODE/_UNICODE を外すが、
# このプラグインのターゲットでは残す（Win32/Flutterのラッパーが前提とする）。
# 分けているのは意図的であり、プラグインからコアの内部ヘッダー（_TCHAR を
# 使うもの）をincludeしないこと。C ABI（bubi_fm77av.h）だけを使う。
include("${CMAKE_CURRENT_SOURCE_DIR}/../src/CMakeLists.txt")

add_library(${PLUGIN_NAME} SHARED
  "include/bubifm77av40ex_core/bubi_fm77_av40_ex_core_plugin_c_api.h"
  "bubi_fm77_av40_ex_core_plugin_c_api.cpp"
  "bubi_fm77_av40_ex_core_plugin.cpp"
  "bubi_fm77_av40_ex_core_plugin.h"
  "bubi_video_texture.cpp"
  "bubi_video_texture.h"
)

# /W4 /WX と _HAS_EXCEPTIONS=0 を含むアプリ側の標準設定。プラグイン自身の
# ソースだけに適用する。コア（native/CMakeLists.txt）には適用しない。
# コアは例外で失敗を伝え（core_thread_main）、警告も無改変のまま残る。
apply_standard_settings(${PLUGIN_NAME})
# ソースはUTF-8（日本語コメント）。ロケールのコードページで読ませると
# C4819が/WXでエラーになり、行末の多バイト文字が改行を飲み込むこともある。
target_compile_options(${PLUGIN_NAME} PRIVATE /utf-8)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME}
  INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
  PRIVATE
    "${BUBI_NATIVE_ROOT}/bridge/include"
)

# コアはプロセス内に1つだけ置く（cpp_homedir などプロセス全域の状態を
# 二重にしない）。macOSはアプリ本体へ -force_load し、プラグインは
# -undefined,dynamic_lookup で実行時に解決するが、Windowsには後者に当たる
# 手段がない。そこでコアをこのプラグインDLLへ丸ごと取り込み、
# BFM_API（__declspec(dllexport)）の関数をこのDLLから公開する。
# Dartも DynamicLibrary.open でこのDLLを開く（lib/src/bindings.dart）。
#
# 静的ライブラリはDLLから参照されないオブジェクトを取り込まないため、
# /WHOLEARCHIVE で全体を取り込む。ターゲットではなくファイルとして
# リンクするのは、コアのPUBLICな使用条件（/FIの強制include、compat/ の
# シムを含むincludeパス）をプラグインのソースへ伝播させないため。
add_dependencies(${PLUGIN_NAME} ${BUBI_PLUGIN_TARGET} bubifm77av40ex_zlib)
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  flutter_wrapper_plugin
  "$<TARGET_FILE:${BUBI_PLUGIN_TARGET}>"
  "$<TARGET_FILE:bubifm77av40ex_zlib>"
)
target_link_options(${PLUGIN_NAME} PRIVATE
  "/WHOLEARCHIVE:$<TARGET_FILE:${BUBI_PLUGIN_TARGET}>"
)

# コアはプラグインDLLへ静的に含まれるため、追加で同梱するDLLはない。
set(bubifm77av40ex_core_bundled_libraries
  ""
  PARENT_SCOPE
)
