# Linux向けプラグイン本体。ウィンドウの内容領域（Flutterの描画面）を
# 直接扱うチャンネル（`bubi_fm77_av40_ex_platform_plugin.cc`）だけを持つ
# （design.md「x1ウィンドウの大きさの調査」、Windows版と同じ役割）。
#
# Flutterのツールが要求する形（PLUGIN_NAME の名前、apply_standard_settings、
# <project>_bundled_libraries）はプラグインテンプレートに合わせる。
cmake_minimum_required(VERSION 3.10)

set(PROJECT_NAME "bubifm77av40ex_platform")
project(${PROJECT_NAME} LANGUAGES CXX)

# この名前はFlutterのツールが生成するビルド定義から参照されるため変えない。
set(PLUGIN_NAME "bubifm77av40ex_platform_plugin")

add_library(${PLUGIN_NAME} SHARED
  "bubi_fm77_av40_ex_platform_plugin.cc"
)

# -Wall -Werror を含むアプリ側の標準設定。
apply_standard_settings(${PLUGIN_NAME})

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter PkgConfig::GTK)

# 同梱する追加ライブラリはない。
set(bubifm77av40ex_platform_bundled_libraries
  ""
  PARENT_SCOPE
)
