#!/usr/bin/env bash
# CocoaPods の script_phase から呼ばれ、native/CMakeLists.txt を
# CMakeでビルドして静的ライブラリを作る。
#
# BASH_SOURCE は Flutter の ephemeral な .symlinks 配下を指すことがある。
# 実体パス（pwd -P）へ正規化しないと、CMakeのソース登録が呼び出し経路ごとに
# 変わり、増分ビルドが毎回作り直しになる。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# Xcodeのビルド環境はPATHが絞られており、cmakeが見えないことがある。
export PATH="/opt/homebrew/bin:/usr/local/bin:${PATH}"

if ! command -v cmake >/dev/null 2>&1; then
  echo "error: cmake が見つかりません。'brew install cmake' を実行してください。" >&2
  exit 1
fi

if [ ! -f "${SCRIPT_DIR}/../../../native/core/upstream/src/emu.h" ]; then
  echo "error: エミュレーションコアが未取得です。" >&2
  echo "       ./scripts/build_native_core.sh fetch を実行してください。" >&2
  exit 1
fi

# Xcodeが渡す環境変数を使う。単体実行時は現在の環境から補う。
ARCHS="${ARCHS:-$(uname -m)}"
SDKROOT="${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}"
CMAKE_ARCHS="${ARCHS// /;}"

BUILD_DIR="${SCRIPT_DIR}/cmake_build/macosx"

# 別のソースパスで構成済みのビルドディレクトリは再構成できない。
if [ -f "${BUILD_DIR}/CMakeCache.txt" ] \
  && ! grep -q "^CMAKE_HOME_DIRECTORY[A-Z:]*=${SCRIPT_DIR}\$" "${BUILD_DIR}/CMakeCache.txt"; then
  echo "  ソースパスが変わったためビルドディレクトリを作り直します。"
  rm -rf "${SCRIPT_DIR}/cmake_build"
fi

echo "=== bubi_fm77av40ex_core: CMake build for macOS ==="
echo "  ARCHS:     ${ARCHS}"
echo "  SDKROOT:   ${SDKROOT}"
echo "  BUILD_DIR: ${BUILD_DIR}"

cmake -S "${SCRIPT_DIR}" -B "${BUILD_DIR}" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES="${CMAKE_ARCHS}" \
  -DCMAKE_OSX_SYSROOT="${SDKROOT}"

cmake --build "${BUILD_DIR}" -j"$(sysctl -n hw.ncpu)"

echo "=== 完了: ${BUILD_DIR}/libbubi_fm77av40ex_core_plugin.a ==="
