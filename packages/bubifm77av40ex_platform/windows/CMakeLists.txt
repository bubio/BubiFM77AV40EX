# Windows向けプラグイン本体。ウィンドウのクライアント領域を直接扱う
# チャンネル（`bubi_fm77_av40_ex_platform_plugin.cpp`）だけを持つ
# （design.md「x1ウィンドウの大きさの調査」）。
#
# Flutterのツールが要求する形（PLUGIN_NAME の名前、apply_standard_settings、
# <project>_bundled_libraries）は`window_manager`と同じプラグインテンプレート
# に合わせる。
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "bubifm77av40ex_platform")
project(${PROJECT_NAME} LANGUAGES CXX)

# この名前はFlutterのツールが生成するビルド定義から参照されるため変えない。
set(PLUGIN_NAME "bubifm77av40ex_platform_plugin")

add_library(${PLUGIN_NAME} SHARED
  "include/bubifm77av40ex_platform/bubi_fm77_av40_ex_platform_plugin.h"
  "bubi_fm77_av40_ex_platform_plugin.cpp"
)

# /W4 /WX と _HAS_EXCEPTIONS=0 を含むアプリ側の標準設定。
apply_standard_settings(${PLUGIN_NAME})
# ソースはUTF-8（日本語コメント）。ロケールのコードページで読ませると
# C4819が/WXでエラーになる（`bubifm77av40ex_core`と同じ理由）。
target_compile_options(${PLUGIN_NAME} PRIVATE /utf-8)

set_target_properties(${PLUGIN_NAME} PROPERTIES
  CXX_VISIBILITY_PRESET hidden)
target_compile_definitions(${PLUGIN_NAME} PRIVATE FLUTTER_PLUGIN_IMPL)

target_include_directories(${PLUGIN_NAME} INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/include")

target_link_libraries(${PLUGIN_NAME} PRIVATE flutter flutter_wrapper_plugin)

# 同梱する追加DLLはない。
set(bubifm77av40ex_platform_bundled_libraries
  ""
  PARENT_SCOPE
)
