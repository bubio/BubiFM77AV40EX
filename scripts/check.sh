#!/usr/bin/env bash
# development_plan.md 11.1 の品質ゲート。ローカルとCIで同じ入口を使う。
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run() {
  echo "==> $*"
  "$@"
}

run fvm flutter pub get
run fvm dart format --output=none --set-exit-if-changed .
run fvm flutter analyze
run fvm flutter test
