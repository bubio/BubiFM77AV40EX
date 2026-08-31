#!/usr/bin/env bash
# macOS成果物のビルド入口。ローカルとCIで同じ手順を使う。
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="${1:-release}"

echo "==> fvm flutter pub get"
fvm flutter pub get

# Flutterアプリはまだネイティブコアをリンクしない（C ABIはM1 WP1）。
# リンクを開始した時点で次の行を有効にする。
# scripts/build_native_core.sh build

echo "==> fvm flutter build macos --${MODE}"
fvm flutter build macos "--${MODE}"

APP="build/macos/Build/Products/$(printf '%s' "${MODE}" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')/BubiFM77AV40EX.app"
if [ -d "${APP}" ]; then
  echo "==> built: ${APP}"
else
  echo "expected app bundle not found: ${APP}" >&2
  exit 1
fi
