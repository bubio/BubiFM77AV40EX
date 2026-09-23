#!/usr/bin/env bash
# macOS配布用DMGの単一入口。ローカルとCIで同じ手順を使う（design.md 15.1/15.2）。
#
# Apple Silicon（arm64）用とIntel（x86_64）用のDMGを別々に作る。
# Flutterは単一アーキテクチャのmacOSビルドに対応しないため、Universalの
# .appを1回だけビルドし、同梱する全Mach-Oを lipo -thin で片方へ絞ってから
# 署名し直す。
#
#   usage: scripts/build_macos_dmg.sh [arm64] [x86_64]
#          引数なしなら両方を作る。
#
# 署名・公証はApple Developer IDの資格情報が環境変数で与えられた場合だけ行う。
# 未設定環境ではad-hoc署名の.appのままDMGを作る
# （development_plan.md 5.4「署名・公証は認証情報をリポジトリへ置かず、
# 未設定環境では署名前成果物まで生成する」）。
#
#   MACOS_SIGN_IDENTITY   : codesignへ渡すDeveloper ID Application識別子
#   MACOS_NOTARY_PROFILE   : xcrun notarytool --keychain-profile の名前
#                             （事前に notarytool store-credentials 済みであること）
#
# 両方が空ならこのスクリプトは署名済み検査（spctl/stapler）を省略する。
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET_ARCHS=("$@")
[ "${#TARGET_ARCHS[@]}" -eq 0 ] && TARGET_ARCHS=(arm64 x86_64)
for arch in "${TARGET_ARCHS[@]}"; do
  case "${arch}" in
    arm64 | x86_64) ;;
    *) echo "error: 未対応のアーキテクチャです: ${arch}" >&2; exit 2 ;;
  esac
done

echo "==> ./scripts/build_macos.sh release"
./scripts/build_macos.sh release

UNIVERSAL_APP="build/macos/Build/Products/Release/BubiFM77AV40EX.app"

VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/^version:[[:space:]]*//' | cut -d '+' -f1)"
if [ -z "${VERSION}" ]; then
  echo "error: pubspec.yamlからバージョンを取得できません" >&2
  exit 1
fi

SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${MACOS_NOTARY_PROFILE:-}"

# --- ライセンス一覧をDMGへ同梱する（.appは変更しない） ---
LICENSES="build/licenses/THIRD_PARTY_LICENSES.txt"
echo "==> ./scripts/generate_license_list.sh ${LICENSES}"
./scripts/generate_license_list.sh "${LICENSES}"

# .app内のUniversal Mach-Oをすべて指定アーキテクチャだけにする。
# 指定アーキテクチャを含まないバイナリがあれば、その機種で起動時に
# 落ちるため失敗させる。
thin_app() {
  local app="$1" arch="$2" file archs tmp count=0
  while IFS= read -r -d '' file; do
    archs="$(lipo -archs "${file}" 2>/dev/null || true)"
    [ -n "${archs}" ] || continue
    if ! printf '%s\n' "${archs}" | grep -qw "${arch}"; then
      echo "error: ${file} が ${arch} を含みません（${archs}）" >&2
      exit 1
    fi
    if [ "${archs}" != "${arch}" ]; then
      tmp="${file}.thin"
      lipo "${file}" -thin "${arch}" -output "${tmp}"
      # 実行権などの属性を保つため、置き換えではなく中身を書き戻す。
      cat "${tmp}" > "${file}"
      rm -f "${tmp}"
    fi
    count=$((count + 1))
  done < <(find "${app}" -type f -print0)

  if [ "${count}" -eq 0 ]; then
    echo "error: ${app} にMach-Oが見つかりません" >&2
    exit 1
  fi
  echo "==> lipo -thin ${arch}: ${count} 個"
}

# lipoで書き換えたため署名は無効になっている。内側から署名し直す。
sign_app() {
  local app="$1"
  if [ -n "${SIGN_IDENTITY}" ]; then
    # 未検証: 実際のDeveloper ID資格情報でこの分岐を通したことはまだない。
    # --deepは検証用フラグであり署名では非推奨（nested frameworkへ個別の
    # identifierを与えられず、公証で弾かれることがある）。資格情報が
    # 揃ったら、Contents/Frameworks/*.frameworkを内側から個別に署名し
    # 直してから.app本体を署名する方式へ見直すこと。
    echo "==> codesign --sign \"${SIGN_IDENTITY}\" --options runtime --deep"
    codesign --force --deep --options runtime --timestamp \
      --preserve-metadata=entitlements \
      --sign "${SIGN_IDENTITY}" "${app}"
  else
    echo "==> MACOS_SIGN_IDENTITY未設定のためad-hoc署名"
    codesign --force --deep --preserve-metadata=entitlements --sign - "${app}"
  fi

  echo "==> codesign --verify --strict --deep"
  codesign --verify --strict --deep "${app}"
}

notarize_app() {
  local app="$1"
  if [ -z "${SIGN_IDENTITY}" ] || [ -z "${NOTARY_PROFILE}" ]; then
    echo "==> 署名またはMACOS_NOTARY_PROFILEが未設定のため公証・stapleを省略"
    return
  fi

  local zip_for_notary
  zip_for_notary="$(dirname "${app}")/BubiFM77AV40EX-notarize.zip"
  rm -f "${zip_for_notary}"
  ditto -c -k --keepParent "${app}" "${zip_for_notary}"

  echo "==> xcrun notarytool submit --wait"
  xcrun notarytool submit "${zip_for_notary}" \
    --keychain-profile "${NOTARY_PROFILE}" --wait

  echo "==> xcrun stapler staple"
  xcrun stapler staple "${app}"

  echo "==> xcrun stapler validate"
  xcrun stapler validate "${app}"

  echo "==> spctl --assess"
  spctl --assess --type execute --verbose "${app}"
}

make_dmg() {
  local app="$1" label="$2"
  local staging="build/macos/dmg-staging"
  rm -rf "${staging}"
  mkdir -p "${staging}"
  cp -R "${app}" "${staging}/"
  ln -s /Applications "${staging}/Applications"
  cp "${LICENSES}" "${staging}/THIRD_PARTY_LICENSES.txt"

  local out_dir="build/macos/dmg"
  mkdir -p "${out_dir}"
  local dmg="${out_dir}/BubiFM77AV40EX-${VERSION}-macos-${label}.dmg"
  rm -f "${dmg}"

  echo "==> hdiutil create ${dmg}"
  hdiutil create \
    -volname "BubiFM77AV40EX ${VERSION}" \
    -srcfolder "${staging}" \
    -format UDZO \
    -fs HFS+ \
    -ov \
    "${dmg}"

  rm -rf "${staging}"
  echo "==> built: ${dmg}"
}

for arch in "${TARGET_ARCHS[@]}"; do
  case "${arch}" in
    arm64) label="apple-silicon" ;;
    x86_64) label="intel" ;;
  esac

  work="build/macos/thin/${arch}"
  rm -rf "${work}"
  mkdir -p "${work}"
  # ditto はframework内のシンボリックリンクと属性を保って複製する。
  ditto "${UNIVERSAL_APP}" "${work}/BubiFM77AV40EX.app"
  app="${work}/BubiFM77AV40EX.app"

  thin_app "${app}" "${arch}"
  sign_app "${app}"
  notarize_app "${app}"
  make_dmg "${app}" "${label}"
done
