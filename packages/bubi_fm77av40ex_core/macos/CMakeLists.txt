# macOS向けの薄いラッパー。実体は ../src/CMakeLists.txt が参照する
# native/CMakeLists.txt にある。
cmake_minimum_required(VERSION 3.24)
project(bubi_fm77av40ex_core_plugin CXX C)

include("${CMAKE_CURRENT_SOURCE_DIR}/../src/CMakeLists.txt")

# CocoaPods は pod 自身のターゲットとして libbubi_fm77av40ex_core.a を作る。
# 同名だとリンク時に取り違えるため、CMake側の出力名を分ける。
set_target_properties(${BUBI_PLUGIN_TARGET} PROPERTIES
  OUTPUT_NAME bubi_fm77av40ex_core_plugin
  ARCHIVE_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}"
)
