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

# --- x86_64/arm64のUniversalバイナリになっているかを確かめる ---
#
# メイン実行ファイルだけでなく、同梱するframeworkやdylibが片方の
# アーキテクチャしか含まないと、その機種でだけ起動時に落ちる。
# ビルドは成功したまま実機でしか気づけない壊れ方なので、
# バンドル内の実行可能ファイルを総なめして検査する。
missing_arch=""
checked=0
while IFS= read -r -d '' binary; do
  archs="$(lipo -archs "${binary}" 2>/dev/null || true)"
  if [ -z "${archs}" ]; then
    continue
  fi
  checked=$((checked + 1))
  if ! printf '%s\n' "${archs}" | grep -qw "x86_64" \
    || ! printf '%s\n' "${archs}" | grep -qw "arm64"; then
    missing_arch="${missing_arch}\n  ${binary}: ${archs}"
  fi
done < <(find "${APP}/Contents/MacOS" "${APP}/Contents/Frameworks" \
  -type f \( -perm -u+x -o -name '*.dylib' \) -print0 2>/dev/null)

if [ "${checked}" -eq 0 ]; then
  echo "error: Universalバイナリ検査の対象が1つも見つかりませんでした。" >&2
  echo "       find のパスやビルド出力構成を確認すること。" >&2
  exit 1
fi

if [ -n "${missing_arch}" ]; then
  echo "error: x86_64/arm64のUniversalになっていないバイナリがあります:" >&2
  printf '%b\n' "${missing_arch}" >&2
  exit 1
fi
echo "==> Universalバイナリ検査: ${checked} 個すべてx86_64/arm64を含む"

# --- flutter_launcher_iconsの出力がバンドルへ反映されているかを確かめる ---
BUILT_INFO_PLIST="${APP}/Contents/Info.plist"
if ! plutil -p "${BUILT_INFO_PLIST}" | grep -q '"CFBundleIconName" => "AppIcon"'; then
  echo "error: ビルド済みInfo.plistにCFBundleIconName=AppIconがありません。" >&2
  echo "       flutter_launcher_iconsの再実行とAssets.xcassetsを確認すること。" >&2
  exit 1
fi
echo "==> アイコン検査: CFBundleIconName=AppIcon"

# --- App Sandboxが成果物へ紛れ込んでいないかを確かめる ---
#
# サンドボックスが有効だと保存先が ~/Library/Containers/ の下へ移り、
# 利用者が自分でROMを置く roms/ へたどり着けなくなる。
# Flutterのテンプレートは既定で有効にするため、再生成やマージで
# 戻りやすい。ビルドも起動も成功したままROMだけが見つからなくなる
# 静かな壊れ方なので、成果物そのものを検査する（design.md 16.1）。
FORBIDDEN_ENTITLEMENT="com.apple.security.app-sandbox"

ENTITLEMENTS="$(codesign -d --entitlements - --xml "${APP}" 2>/dev/null || true)"
if [ -z "${ENTITLEMENTS}" ]; then
  echo "==> entitlements検査: App Sandboxの指定なし"
elif printf '%s' "${ENTITLEMENTS}" | grep -q "${FORBIDDEN_ENTITLEMENT}"; then
  echo "error: App Sandboxが有効です: ${FORBIDDEN_ENTITLEMENT}" >&2
  echo "       macos/Runner/*.entitlements から外すこと。" >&2
  exit 1
else
  echo "==> entitlements検査: App Sandboxは無効"
fi
