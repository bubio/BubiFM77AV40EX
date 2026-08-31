#!/usr/bin/env bash
# 配布物へ同梱する依存パッケージのライセンス一覧を生成する。
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

OUT="${1:-build/licenses/THIRD_PARTY_LICENSES.txt}"
mkdir -p "$(dirname "${OUT}")"

fvm flutter pub get >/dev/null
fvm dart run tool/collect_licenses.dart "${OUT}"

echo "==> wrote ${OUT}"
