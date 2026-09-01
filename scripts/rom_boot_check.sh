#!/usr/bin/env bash
# 実ROMでの起動確認（development_plan.md 6 WP2 最終項目）。
#
# CIでは走らせない。利用者が自分のROMを
# ~/Library/Application Support/BubiFM77AV40EX/roms/ へ置いた機械でだけ動く。
# ROMを1つも読み込めない環境では、その旨を出して0で終わる。
#
# 画面はROM由来の出力なのでリポジトリへは書かない。
# 出力先はTMPDIR配下に作る。
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${REPO_ROOT}/build/native"

APP_SUPPORT="${HOME}/Library/Application Support/BubiFM77AV40EX"
ROM_DIR="${BUBI_ROM_DIR:-${APP_SUPPORT}/roms}"

if [ ! -d "${ROM_DIR}" ] || [ -z "$(ls -A "${ROM_DIR}" 2>/dev/null)" ]; then
  echo "ROMが置かれていないため起動確認は行いません: \${HOME}/Library/Application Support/BubiFM77AV40EX/roms"
  exit 0
fi

OUT_DIR="${BUBI_ROM_CHECK_OUT:-$(mktemp -d "${TMPDIR:-/tmp}/bubi-rom-boot.XXXXXX")}"
mkdir -p "${OUT_DIR}"

# 利用者のROMも設定も汚さないよう、home_dir は使い捨てにする。
HOME_DIR="${OUT_DIR}/home"
mkdir -p "${HOME_DIR}"

"${REPO_ROOT}/scripts/build_native_core.sh" build >/dev/null

FRAMES="${BUBI_ROM_CHECK_FRAMES:-300}"
"${BUILD_DIR}/rom_boot_check" "${HOME_DIR}" "${ROM_DIR}" "${OUT_DIR}" "${FRAMES}"

echo
echo "画面の書き出し先: ${OUT_DIR}"
