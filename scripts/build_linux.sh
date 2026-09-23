#!/usr/bin/env bash
# Linux成果物のビルド入口。ローカルとCIで同じ手順を使う。
#
# ビルドしたマシンのアーキテクチャ（x64 / arm64）向けのbundleを作る。
# Flutterはクロスビルドに対応しないため、arm64はarm64機で実行する。
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

MODE="${1:-release}"

# packages/bubifm77av40ex_core のCMakeビルドが native/core/upstream を参照する。
echo "==> ./scripts/build_native_core.sh fetch"
./scripts/build_native_core.sh fetch

echo "==> fvm flutter pub get"
fvm flutter pub get

echo "==> fvm flutter build linux --${MODE}"
fvm flutter build linux "--${MODE}"

case "$(uname -m)" in
  x86_64) FLUTTER_ARCH="x64" ;;
  aarch64 | arm64) FLUTTER_ARCH="arm64" ;;
  *) echo "error: 未対応のアーキテクチャです: $(uname -m)" >&2; exit 1 ;;
esac

BUNDLE="build/linux/${FLUTTER_ARCH}/${MODE}/bundle"
if [ ! -x "${BUNDLE}/BubiFM77AV40EX" ]; then
  echo "expected bundle not found: ${BUNDLE}" >&2
  exit 1
fi
echo "==> built: ${BUNDLE}"
