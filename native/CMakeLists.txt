# eFM77AV40EX コア（無改変）+ ホスト非依存OSD + 最小ホストのビルド定義。
#
# コア本体は native/core/upstream/ のサブモジュール（固定リビジョン）を
# そのまま参照し、1ファイルもコピー・改変しない。ホスト側の差異は
# native/bridge/ とこの定義だけに置く（design.md 3.2）。
cmake_minimum_required(VERSION 3.24)

project(bubi_fm77av40ex_core CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_C_STANDARD 11)

# ホスト側の検査用ターゲット（最小ホスト、C ABIテスト、Dart FFI検証用dylib）を
# 作るかどうか。scripts/ から呼ぶときは ON、Flutterプラグインから
# add_subdirectory() するときは OFF にして、アプリのビルドへ
# 実行ファイルやctestの登録を持ち込まない。
option(BUBI_BUILD_HOST_TOOLS "Build host-side smoke/test executables" ON)

if(APPLE)
  # .app の LSMinimumSystemVersion と一致させる。指定しないとビルド機の
  # SDK最小版が刻まれ、それより古いmacOSで起動できなくなる。
  set(CMAKE_OSX_DEPLOYMENT_TARGET "13.5" CACHE STRING "" FORCE)
endif()

set(CORE_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/core/upstream")
set(CORE_SRC "${CORE_ROOT}/src")

if(NOT EXISTS "${CORE_SRC}/emu.h")
  message(FATAL_ERROR
    "エミュレーションコアが未取得です。scripts/build_native_core.sh fetch を実行してください。")
endif()

# vc++2017/fm77av40ex.vcxproj の ClCompile 一覧から src/win32/* を除いたもの。
# win32のOSD実装だけをホスト非依存の実装へ差し替える。
# 一覧の増減はこのプロジェクトファイルを正とし、独自に取捨選択しない。
set(CORE_SOURCES
  common.cpp
  config.cpp
  emu.cpp
  fifo.cpp
  fileio.cpp
  vm/and.cpp
  vm/ay_3_891x.cpp
  vm/beep.cpp
  vm/datarec.cpp
  vm/disk.cpp
  vm/event.cpp
  vm/i8251.cpp
  vm/mb8877.cpp
  vm/mc6809.cpp
  vm/mc6809_base.cpp
  vm/memory.cpp
  vm/noise.cpp
  vm/pcm1bit.cpp
  vm/prnfile.cpp
  vm/ym2203.cpp
  vm/z80.cpp
  vm/fm7/display.cpp
  vm/fm7/dummydevice.cpp
  vm/fm7/floppy.cpp
  vm/fm7/fm7.cpp
  vm/fm7/fm7_mainio.cpp
  vm/fm7/fm7_mainmem.cpp
  vm/fm7/hd6844.cpp
  vm/fm7/jcommcard.cpp
  vm/fm7/joystick.cpp
  vm/fm7/kanjirom.cpp
  vm/fm7/keyboard.cpp
  vm/fm7/mainmem_mmr.cpp
  vm/fm7/mainmem_page2.cpp
  vm/fm7/mainmem_readseq.cpp
  vm/fm7/mainmem_utils.cpp
  vm/fm7/mainmem_writeseq.cpp
  vm/fm7/mb61vh010.cpp
  vm/fm7/sound.cpp
  vm/fm7/vram.cpp
  vm/fmgen/fmgen.cpp
  vm/fmgen/fmtimer.cpp
  vm/fmgen/opna.cpp
  vm/fmgen/psg.cpp
)
list(TRANSFORM CORE_SOURCES PREPEND "${CORE_SRC}/")

# debugger.cpp は vcxproj に含まれるが、OSD_SDL経路では
# EMU::debugger_thread_id が int として宣言される一方、pthread_create へ
# pthread_t* として渡すため upstream のままではコンパイルできない。
# デバッガーはP2（DBG-01/DBG-02）であり、M0では
# bridge/compat/debugger_stubs.cpp のスタブで代替する。
# P2着手時に、コアを変更しない形での有効化方法を改めて技術検証する。

# ホスト非依存OSDとWindows互換シム。GLOBは新規ファイルを追跡しないため明示する。
# 製品用C ABI（bridge/src/bubi_fm77av.cpp）もこのライブラリに含める。
# Flutterプラグインはこの1つの .a を -force_load するため、
# 公開シンボルとコア本体が同じアーカイブに入っている必要がある。
set(BRIDGE_SOURCES
  bridge/osd/sdl/osd.cpp
  bridge/osd/sdl/osd_bitmap.cpp
  bridge/osd/sdl/osd_console.cpp
  bridge/osd/sdl/osd_input.cpp
  bridge/osd/sdl/osd_midi.cpp
  bridge/osd/sdl/osd_screen.cpp
  bridge/osd/sdl/osd_sound.cpp
  bridge/src/bubi_fm77av.cpp
  bridge/compat/core_feature_shim.cpp
  bridge/compat/core_host_symbols.cpp
  bridge/compat/debugger_stubs.cpp
)
list(TRANSFORM BRIDGE_SOURCES PREPEND "${CMAKE_CURRENT_SOURCE_DIR}/")

add_library(bubi_fm77av40ex_core STATIC ${CORE_SOURCES} ${BRIDGE_SOURCES})

target_include_directories(bubi_fm77av40ex_core
  PUBLIC
    # 製品用 C ABI の公開ヘッダー
    "${CMAKE_CURRENT_SOURCE_DIR}/bridge/include"
    # Windows専用ヘッダー（<io.h>, <malloc.h>）の互換シム。
    # コアを1行も変更せずに非Windowsでビルドするために置く。
    "${CMAKE_CURRENT_SOURCE_DIR}/bridge/compat"
    "${CORE_SRC}"
    # emu.h の #include "sdl/osd.h" は upstream に実体がないため、
    # インクルードパス側の bridge/osd/sdl/osd.h が解決される。
    # ディレクトリ名 sdl は upstream のinclude文が要求する名前であり、
    # SDLライブラリ・ヘッダーには一切依存しない（BluePrint 禁止事項）。
    "${CMAKE_CURRENT_SOURCE_DIR}/bridge/osd"
)

target_compile_definitions(bubi_fm77av40ex_core
  PUBLIC
    # 機種選択。vc++2017/fm77av40ex.vcxproj と同じ唯一の機種定義。
    _FM77AV40EX
    # emu.h で OSD_SDL を選ばせるためのスイッチ。SDLは使用しない。
    _USE_SDL
    # upstream common.h は SUPPORT_TCHAR_TYPE 無効時に _ftprintf を printf へ
    # 割り当てるが、_ftprintf(fp, ...) の呼び出しには fprintf が正しい。
    # 同ヘッダーが #ifndef で守っているため、先に定義して差し替える。
    _ftprintf=fprintf
)

# コアはMSVC前提で書かれているため、clang/libc++ で不足する標準ヘッダーを
# プリアンブルで強制インクルードする。upstreamのソースは変更しない。
target_compile_options(bubi_fm77av40ex_core PUBLIC
  -include "${CMAKE_CURRENT_SOURCE_DIR}/bridge/compat/bubi_core_prelude.h"
)

target_compile_options(bubi_fm77av40ex_core PRIVATE
  -Wno-writable-strings       # MSVCが許す char* への文字列リテラル代入
  -Wno-invalid-source-encoding # コメント中のShift-JIS
  -Wno-register                # C++17で削除された register 指定子
  -Wno-unused-value
  -Wno-switch
  -Wno-deprecated-declarations
)

# 該当3ファイルだけに追加のシムを差し込む（理由はシムのヘッダーコメント参照）。
set_source_files_properties(
  "${CORE_SRC}/vm/mc6809.cpp"
  "${CORE_SRC}/vm/mc6809_base.cpp"
  "${CORE_SRC}/vm/fm7/hd6844.cpp"
  PROPERTIES COMPILE_OPTIONS
    "-include;${CMAKE_CURRENT_SOURCE_DIR}/bridge/compat/core_feature_shim.h"
)

# upstream は USE_ZLIB 定義時だけ zlib を使う（fileio.h）。FM77AV40EX構成では
# 定義していないため、zlib へはリンクしない。gzip入りイメージへ対応する場合は
# USE_ZLIB を明示的に定義し、そのときに ZLIB を追加する。

if(BUBI_BUILD_HOST_TOOLS)
  # 最小ホスト: VMを生成して破棄できることだけを確認する（development_plan.md 5.2）。
  # ROMを1つも必要とせず、CIで実行できる。
  add_executable(core_smoke "${CMAKE_CURRENT_SOURCE_DIR}/host/core_smoke.cpp")
  target_link_libraries(core_smoke PRIVATE bubi_fm77av40ex_core)
  target_include_directories(core_smoke PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}/bridge/compat")

  # 製品用 C ABI の検査（development_plan.md 6 WP1）。
  # 見張りの自己検証にテストフックが要るため、この実行ファイルにだけ
  # BUBI_ENABLE_TEST_HOOKS を定義する。配布物には含まれない。
  add_executable(session_test
    "${CMAKE_CURRENT_SOURCE_DIR}/host/session_test.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/bridge/src/bubi_fm77av.cpp"
  )
  target_compile_definitions(session_test PRIVATE BUBI_ENABLE_TEST_HOOKS)
  target_link_libraries(session_test PRIVATE bubi_fm77av40ex_core)

  # 同じC ABIをDart FFIから呼べることを確かめるための共有ライブラリ。
  # アプリへの組み込みは packages/bubi_fm77av40ex_core/ の静的リンクで行う
  # （design.md 16.1）。ここはシンボル解決と呼び出しの検証専用である。
  add_library(bubi_fm77av40ex_shared SHARED
    "${CMAKE_CURRENT_SOURCE_DIR}/bridge/src/bubi_fm77av.cpp"
  )
  set_target_properties(bubi_fm77av40ex_shared PROPERTIES OUTPUT_NAME bubi_fm77av40ex)
  target_link_libraries(bubi_fm77av40ex_shared PRIVATE bubi_fm77av40ex_core)

  enable_testing()
  # 書込み先をビルドディレクトリ配下へ閉じ込め、ホームディレクトリを汚さない。
  add_test(NAME core_smoke COMMAND core_smoke "${CMAKE_CURRENT_BINARY_DIR}/smoke-home")
  add_test(NAME session_test COMMAND session_test "${CMAKE_CURRENT_BINARY_DIR}/session-home")
endif()
