# Linux向けの薄いラッパー。実体は ../src/CMakeLists.txt が参照する
# native/CMakeLists.txt にある（design.md 16.1）。
#
# Flutterのツールが要求する形（PLUGIN_NAME の名前、apply_standard_settings、
# <project>_bundled_libraries）はプラグインテンプレートに合わせる。
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "bubifm77av40ex_core")
project(${PROJECT_NAME} LANGUAGES CXX C)

# この名前はFlutterのツールが生成するビルド定義から参照されるため変えない。
set(PLUGIN_NAME "bubifm77av40ex_core_plugin")

include("${CMAKE_CURRENT_SOURCE_DIR}/../src/CMakeLists.txt")

add_library(${PLUGIN_NAME} SHARED
  "bubi_fm77_av40_ex_core_plugin.cc"
  "bubi_video_texture.cc"
)

# -Wall -Werror を含むアプリ側の標準設定。プラグイン自身のソースだけに
# 適用する。コア（native/CMakeLists.txt）には適用しない。
apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_STANDARD 17
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME}
  INTERFACE
    "${CMAKE_CURRENT_SOURCE_DIR}/include"
  PRIVATE
    "${BUBI_NATIVE_ROOT}/bridge/include"
)

# コアはプロセス内に1つだけ置く（cpp_homedir などプロセス全域の状態を
# 二重にしない）。Windows版と同じく、コアをこのプラグインの共有ライブラリへ
# 丸ごと取り込み、BFM_API（visibility("default")）の関数をここから公開する。
# Dartも DynamicLibrary.open でこの共有ライブラリを開く
# （lib/src/bindings.dart）。ランナーがリンク済みのため同じ実体が返る。
#
# 静的ライブラリは参照されないオブジェクトを取り込まないため、
# --whole-archive で全体を取り込む。ターゲットではなくファイルとして
# リンクするのは、コアのPUBLICな使用条件（-include の強制include、
# compat/ のシムを含むincludeパス）をプラグインのソースへ伝播させないため。
find_package(Threads REQUIRED)
add_dependencies(${PLUGIN_NAME} ${BUBI_PLUGIN_TARGET})
target_link_libraries(${PLUGIN_NAME} PRIVATE
  flutter
  PkgConfig::GTK
  "-Wl,--whole-archive"
  "$<TARGET_FILE:${BUBI_PLUGIN_TARGET}>"
  "-Wl,--no-whole-archive"
  Threads::Threads
  ${CMAKE_DL_LIBS}
)

# コアはプラグインの共有ライブラリへ静的に含まれるため、追加で同梱する
# ライブラリはない。
set(bubifm77av40ex_core_bundled_libraries
  ""
  PARENT_SCOPE
)
