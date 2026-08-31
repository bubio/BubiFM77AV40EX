#!/usr/bin/env bash
# 技術検証spikeのうち、ctestに載せない検査を実行する
# （development_plan.md 5.3）。
#
# session_spike 本体は ctest（scripts/build_native_core.sh test）が実行する。
# ここは同じバイナリに対するリーク検査と、Dart FFI からの呼び出し検証を行う。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build/native"

log() { printf '==> %s\n' "$*"; }

"${REPO_ROOT}/scripts/build_native_core.sh" build >/dev/null

SPIKE="${BUILD_DIR}/session_spike"
SPIKE_HOME="${BUILD_DIR}/spike-home"
SPIKE_DYLIB="${BUILD_DIR}/libbfm_session_spike.dylib"

# --- リーク検査（合格条件「リークがない」） ---
if [ "$(uname -s)" = "Darwin" ]; then
  log "leak check (leaks)"
  # leaks(1) は「なし=0 / あり=1」で終わる。判定は終了コードで行い、
  # ツール自体を実行できない場合と取り違えない。
  leaks_output=""
  leaks_status=0
  if ! leaks_output="$(leaks --atExit -- "${SPIKE}" "${SPIKE_HOME}" 2>&1)"; then
    leaks_status=$?
  fi

  if printf '%s' "${leaks_output}" | grep -qE 'total leaked bytes'; then
    printf '%s' "${leaks_output}" | grep -E 'total leaked bytes'
    if [ "${leaks_status}" -ne 0 ]; then
      echo "error: リークを検出しました" >&2
      exit 1
    fi
  else
    # サンドボックス等で計測できないことがある。未実施として扱い、
    # 検出0と偽らない。
    echo "warning: leaks(1) を実行できませんでした。リーク検査は未実施です。" >&2
  fi
else
  log "leak check: skipped (macOS以外)"
fi

# --- Dart FFI からの呼び出し（M1 WP1が最初に当たる境界） ---
if [ -f "${SPIKE_DYLIB}" ]; then
  log "dart ffi spike"
  (cd "${REPO_ROOT}" && fvm dart run native/spike/session/dart_ffi_spike.dart \
    "${SPIKE_DYLIB}" "${SPIKE_HOME}")
else
  echo "error: ${SPIKE_DYLIB} がありません" >&2
  exit 1
fi

log "spikes passed"
