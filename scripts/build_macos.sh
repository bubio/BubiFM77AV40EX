#!/usr/bin/env bash
# macOS成果物のビルド入口。ローカルとCIで同じ手順を使う。
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="${1:-release}"

# packages/bubi_fm77av40ex_core のCMakeビルドが native/core/upstream を参照する。
# 取得は冪等なので毎回呼ぶ。
echo "==> ./scripts/build_native_core.sh fetch"
./scripts/build_native_core.sh fetch

echo "==> fvm flutter pub get"
fvm flutter pub get

echo "==> fvm flutter build macos --${MODE}"
fvm flutter build macos "--${MODE}"

APP="build/macos/Build/Products/$(printf '%s' "${MODE}" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')/BubiFM77AV40EX.app"
if [ ! -d "${APP}" ]; then
  echo "expected app bundle not found: ${APP}" >&2
  exit 1
fi
echo "==> built: ${APP}"

# --- FFIシンボルがリンク後も残っているかを確かめる ---
#
# -force_load か -export_dynamic のどちらが欠けても、ビルドは成功したまま
# 実行時の DynamicLibrary.process() だけが失敗する。静かに壊れる経路なので
# 成果物そのものを検査する。
#
# Debugビルドの Contents/MacOS/ は起動用スタブで、本体は別のdylibにある。
# 判定が曖昧になるため release と profile だけを対象にする。
if [ "${MODE}" = "debug" ]; then
  echo "==> FFIシンボル検査: debugビルドのため省略"
  exit 0
fi

BINARY="${APP}/Contents/MacOS/BubiFM77AV40EX"
EXPECTED="$(grep -o 'bfm_[a-z_]*(' native/bridge/include/bubi_fm77av.h \
  | tr -d '(' | sort -u)"

missing=""
for symbol in ${EXPECTED}; do
  if ! nm -gU "${BINARY}" | grep -q " _${symbol}\$"; then
    missing="${missing} ${symbol}"
  fi
done

if [ -n "${missing}" ]; then
  echo "error: FFIシンボルが実行ファイルにありません:${missing}" >&2
  echo "       podspec の -force_load と -Wl,-export_dynamic を確認すること。" >&2
  exit 1
fi
echo "==> FFIシンボル検査: $(printf '%s\n' ${EXPECTED} | wc -l | tr -d ' ') 個すべて存在"
