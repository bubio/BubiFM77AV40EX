# 全OS共通のビルド入口。
#
# ビルド定義の正は native/CMakeLists.txt であり、ここはそれを呼ぶ薄い層に
# 留める（design.md 16.1）。ソース一覧をこちらへ複製しない。
#
# 各OSの macos/ linux/ windows/ … の CMakeLists.txt がこのファイルを
# include() する。

get_filename_component(BUBI_NATIVE_ROOT
  "${CMAKE_CURRENT_LIST_DIR}/../../../native" ABSOLUTE)

if(NOT EXISTS "${BUBI_NATIVE_ROOT}/CMakeLists.txt")
  message(FATAL_ERROR
    "native/CMakeLists.txt が見つかりません: ${BUBI_NATIVE_ROOT}")
endif()

# アプリのビルドへ検査用の実行ファイルやctestの登録を持ち込まない。
set(BUBI_BUILD_HOST_TOOLS OFF CACHE BOOL "" FORCE)

add_subdirectory("${BUBI_NATIVE_ROOT}" "${CMAKE_CURRENT_BINARY_DIR}/native")

# アプリへ -force_load する静的ライブラリのターゲット名。
set(BUBI_PLUGIN_TARGET bubi_fm77av40ex_core)
