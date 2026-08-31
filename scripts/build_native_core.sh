#!/usr/bin/env bash
# ネイティブコア（eFM77AV40EX + bridge）の取得・構成・ビルド・検証を行う単一入口。
# ローカルとCIは必ず本スクリプトを呼び、手順を二重管理しない。
#
# コアは native/core/upstream のGitサブモジュールとして固定リビジョンを参照し、
# 1ファイルもコピー・改変しない。非Windows向けの差異は native/bridge/ と
# native/CMakeLists.txt だけに置く（design.md 3.2 / BluePrint 禁止事項）。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_PATH="native/core/upstream"
CORE_DIR="${REPO_ROOT}/${CORE_PATH}"
BUILD_DIR="${REPO_ROOT}/build/native"
BUILD_TYPE="${BUBI_NATIVE_BUILD_TYPE:-Release}"

# specification.md 1章で解析対象として固定したリビジョン。
PINNED_REVISION="0c07c4e33bb7f5228137eeb13f7b196cc5db4e85"

usage() {
  cat <<'USAGE'
usage: scripts/build_native_core.sh <command>

commands:
  fetch      固定リビジョンのコアをサブモジュールとして取得する
  verify     コアが固定リビジョンかつ無改変であることを検査する
  configure  CMakeの構成を行う
  build      bridgeとコアをビルドする（configureを含む）
  test       最小ホスト（ROM不要）を実行する
  licenses   同梱すべきライセンス・著作権表示を一覧する
  status     現在の状態を表示する
  all        verify → build → test を順に実行する
USAGE
}

log() { printf '==> %s\n' "$*"; }
fail() { printf 'error: %s\n' "$*" >&2; exit 1; }

fetch() {
  log "サブモジュール ${CORE_PATH} を取得する"
  git -C "${REPO_ROOT}" submodule update --init --recursive -- "${CORE_PATH}"
  verify
}

verify() {
  [ -f "${CORE_DIR}/src/emu.h" ] \
    || fail "コアが未取得です。scripts/build_native_core.sh fetch を実行してください。"

  local head
  head="$(git -C "${CORE_DIR}" rev-parse HEAD)"
  [ "${head}" = "${PINNED_REVISION}" ] \
    || fail "コアのリビジョンが固定値と異なります。期待 ${PINNED_REVISION} / 実際 ${head}"

  # 追跡ファイルの変更だけでなく、未追跡ファイルの追加も検出する。
  # 検出したいのは「src/sdl/osd.h を置く」ような後付けの改変である。
  local dirty
  dirty="$(git -C "${CORE_DIR}" status --porcelain --untracked-files=all)"
  if [ -n "${dirty}" ]; then
    printf 'error: コアに改変または未追跡ファイルがあります。\n' >&2
    printf '%s\n' "${dirty}" >&2
    fail "コアは無改変で使用します（BluePrint 禁止事項）。"
  fi

  log "コアは固定リビジョン ${PINNED_REVISION} で無改変"
}

configure() {
  verify
  log "cmake -S native -B build/native (${BUILD_TYPE})"
  cmake -S "${REPO_ROOT}/native" -B "${BUILD_DIR}" -DCMAKE_BUILD_TYPE="${BUILD_TYPE}"
}

build() {
  configure
  log "cmake --build build/native"
  cmake --build "${BUILD_DIR}" --parallel
}

run_test() {
  [ -x "${BUILD_DIR}/core_smoke" ] \
    || fail "最小ホストが未ビルドです。scripts/build_native_core.sh build を実行してください。"
  log "ctest (最小ホスト。ROMを必要としない)"
  ctest --test-dir "${BUILD_DIR}" --output-on-failure
}

licenses() {
  [ -d "${CORE_DIR}/license" ] || fail "コアが未取得です。"

  local out="${1:-${REPO_ROOT}/build/licenses/CORE_LICENSES.txt}"
  mkdir -p "$(dirname "${out}")"

  {
    printf 'BubiFM77AV40EX emulation core licenses\n'
    printf 'core revision: %s\n\n' "$(git -C "${CORE_DIR}" rev-parse HEAD)"

    printf '## 配布物へ同梱するライセンス文書\n\n'
    printf -- '- license/COPYING.txt (GNU GPL v2)\n'
    printf '    Common Source Code Project 全体のライセンス。配布物へ必ず含める。\n\n'

    printf '## 本ビルドでは使用しないライセンス文書\n\n'
    printf '   FM77AV40EX構成でコンパイルしないコンポーネントのもの。\n'
    printf '   同梱の要否は該当機能を追加する時点で再判定する。\n\n'
    (cd "${CORE_DIR}" && find license -type f ! -name COPYING.txt | sort) \
      | sed 's/^/- /'
    printf '\n'

    printf '## 実際にコンパイルするソースの著作権表示\n\n'
    local sources
    sources="$(grep -oE '^  (vm/)?[A-Za-z0-9_/]+\.cpp' "${REPO_ROOT}/native/CMakeLists.txt" | sed 's/^  //')"
    printf '%s\n' "${sources}" | while read -r rel; do
      [ -n "${rel}" ] || continue
      [ -f "${CORE_DIR}/src/${rel}" ] || continue
      sed -n '1,20p' "${CORE_DIR}/src/${rel}" \
        | grep -iE 'author|copyright|\(c\)' || true
    done | sed 's/^[[:space:]/*]*//;s/[[:space:]]*$//' | sort -u | sed 's/^/- /'
    printf '\n'

    printf '## 注記\n\n'
    printf -- '- src/vm/fmgen/* は cisc 氏の FM Sound Generator であり、\n'
    printf '  license/ 配下に個別の文書がない。表示は各ソース先頭の著作権行による。\n'
    printf -- '- 原著作者表記（TAKEDA, toshiya ほか）と readme.txt の謝辞は\n'
    printf '  配布物のライセンス表示へ含める。\n'
  } > "${out}"

  log "wrote ${out}"
  cat "${out}"
}

status() {
  printf 'repo root  : %s\n' "${REPO_ROOT}"
  printf 'core path  : %s\n' "${CORE_PATH}"
  printf 'build dir  : %s\n' "${BUILD_DIR}"
  printf 'pinned rev : %s\n' "${PINNED_REVISION}"
  if [ -f "${CORE_DIR}/src/emu.h" ]; then
    printf 'core rev   : %s\n' "$(git -C "${CORE_DIR}" rev-parse HEAD)"
    if [ -z "$(git -C "${CORE_DIR}" status --porcelain --untracked-files=all)" ]; then
      printf 'core state : clean (無改変)\n'
    else
      printf 'core state : DIRTY\n'
    fi
  else
    printf 'core rev   : absent (未取得)\n'
  fi
}

case "${1:-}" in
  fetch) fetch ;;
  verify) verify ;;
  configure) configure ;;
  build) build ;;
  test) run_test ;;
  licenses) licenses ;;
  status) status ;;
  all) verify; build; run_test ;;
  -h|--help|help|"") usage ;;
  *) usage; exit 2 ;;
esac
