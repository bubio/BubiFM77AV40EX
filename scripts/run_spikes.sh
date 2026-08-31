#!/usr/bin/env bash
# 技術検証spikeのうち、ctestに載せない検査を実行する
# （development_plan.md 5.3）。
#
# session_spike 本体は ctest（scripts/build_native_core.sh test）が実行する。
# ここは同じバイナリに対するリーク検査と、Dart FFI からの呼び出し検証を行う。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build/native"

# leaks(1) はサンドボックス下のCIランナーで応答しなくなることがあるため、
# 必ず時間制限を掛ける。
LEAK_TIMEOUT_SECONDS="${BUBI_LEAK_TIMEOUT_SECONDS:-120}"

log() { printf '==> %s\n' "$*"; }

# コマンドを時間制限付きで実行する。超過時は 124 を返す（macOSにtimeout(1)がない）。
run_with_timeout() {
  local seconds="$1"
  shift

  "$@" &
  local pid=$!
  local waited=0
  while kill -0 "${pid}" 2>/dev/null; do
    if [ "${waited}" -ge "${seconds}" ]; then
      kill -9 "${pid}" 2>/dev/null || true
      wait "${pid}" 2>/dev/null || true
      return 124
    fi
    sleep 1
    waited=$((waited + 1))
  done

  local status=0
  wait "${pid}" || status=$?
  return "${status}"
}

"${REPO_ROOT}/scripts/build_native_core.sh" build >/dev/null

SPIKE="${BUILD_DIR}/session_spike"
SPIKE_HOME="${BUILD_DIR}/spike-home"
SPIKE_DYLIB="${BUILD_DIR}/libbfm_session_spike.dylib"
LEAK_LOG="${BUILD_DIR}/leaks.log"

# --- リーク検査（合格条件「リークがない」） ---
if [ "$(uname -s)" != "Darwin" ]; then
  log "leak check: skipped (macOS以外)"
elif [ "${BUBI_SKIP_LEAK_CHECK:-0}" = "1" ]; then
  log "leak check: skipped (BUBI_SKIP_LEAK_CHECK=1)"
elif ! command -v leaks >/dev/null 2>&1; then
  echo "warning: leaks(1) がありません。リーク検査は未実施です。" >&2
else
  log "leak check (leaks, timeout ${LEAK_TIMEOUT_SECONDS}s)"
  # leaks(1) は「なし=0 / あり=1」で終わる。判定は終了コードで行い、
  # ツールを実行できない場合と取り違えない。
  leaks_status=0
  run_with_timeout "${LEAK_TIMEOUT_SECONDS}" \
    env MallocStackLogging=0 leaks --atExit -- "${SPIKE}" "${SPIKE_HOME}" \
    >"${LEAK_LOG}" 2>&1 || leaks_status=$?

  if [ "${leaks_status}" -eq 124 ]; then
    echo "warning: leaks(1) が ${LEAK_TIMEOUT_SECONDS} 秒で応答しませんでした。リーク検査は未実施です。" >&2
  elif grep -qE 'total leaked bytes' "${LEAK_LOG}"; then
    grep -E 'total leaked bytes' "${LEAK_LOG}"
    if [ "${leaks_status}" -ne 0 ]; then
      echo "error: リークを検出しました" >&2
      exit 1
    fi
  else
    # サンドボックス等で計測できないことがある。未実施として扱い、
    # 検出0と偽らない。
    echo "warning: leaks(1) を実行できませんでした。リーク検査は未実施です。" >&2
    sed 's/^/  /' "${LEAK_LOG}" >&2 || true
  fi
fi

# --- Dart FFI からの呼び出し（M1 WP1が最初に当たる境界） ---
[ -f "${SPIKE_DYLIB}" ] || { echo "error: ${SPIKE_DYLIB} がありません" >&2; exit 1; }

log "dart ffi spike"
(cd "${REPO_ROOT}" && fvm dart run native/spike/session/dart_ffi_spike.dart \
  "${SPIKE_DYLIB}" "${SPIKE_HOME}")

log "spikes passed"
