#!/usr/bin/env bash
# macOS配布用DMGの単一入口。ローカルとCIで同じ手順を使う（design.md 15.1/15.2）。
#
# 署名・公証はApple Developer IDの資格情報が環境変数で与えられた場合だけ行う。
# 未設定環境では署名前（ad-hoc署名済み）の.appのままDMGを作る
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

echo "==> ./scripts/build_macos.sh release"
./scripts/build_macos.sh release

APP="build/macos/Build/Products/Release/BubiFM77AV40EX.app"

VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/^version:[[:space:]]*//' | cut -d '+' -f1)"
if [ -z "${VERSION}" ]; then
  echo "error: pubspec.yamlからバージョンを取得できません" >&2
  exit 1
fi

# --- 署名（資格情報がある場合だけ） ---
SIGN_IDENTITY="${MACOS_SIGN_IDENTITY:-}"
NOTARY_PROFILE="${MACOS_NOTARY_PROFILE:-}"

if [ -n "${SIGN_IDENTITY}" ]; then
  # 未検証: 実際のDeveloper ID資格情報でこの分岐を通したことはまだない。
  # --deepは検証用フラグであり署名では非推奨（nested frameworkへ個別の
  # identifierを与えられず、公証で弾かれることがある）。資格情報が
  # 揃ったら、Contents/Frameworks/*.frameworkを内側から個別に署名し
  # 直してから.app本体を署名する方式へ見直すこと。
  echo "==> codesign --sign \"${SIGN_IDENTITY}\" --options runtime --deep"
  codesign --force --deep --options runtime --timestamp \
    --sign "${SIGN_IDENTITY}" "${APP}"

  echo "==> codesign --verify --strict --deep"
  codesign --verify --strict --deep "${APP}"

  if [ -n "${NOTARY_PROFILE}" ]; then
    ZIP_FOR_NOTARY="build/macos/BubiFM77AV40EX-notarize.zip"
    rm -f "${ZIP_FOR_NOTARY}"
    ditto -c -k --keepParent "${APP}" "${ZIP_FOR_NOTARY}"

    echo "==> xcrun notarytool submit --wait"
    xcrun notarytool submit "${ZIP_FOR_NOTARY}" \
      --keychain-profile "${NOTARY_PROFILE}" --wait

    echo "==> xcrun stapler staple"
    xcrun stapler staple "${APP}"

    echo "==> xcrun stapler validate"
    xcrun stapler validate "${APP}"

    echo "==> spctl --assess"
    spctl --assess --type execute --verbose "${APP}"
  else
    echo "==> MACOS_NOTARY_PROFILE未設定のため公証・stapleを省略"
  fi
else
  echo "==> MACOS_SIGN_IDENTITY未設定のため署名・公証をad-hocのまま省略"
fi

echo "==> codesign --verify --strict --deep（署名有無に関わらず検査）"
codesign --verify --strict --deep "${APP}"

# --- ライセンス一覧をDMGへ同梱する（.appは変更しない） ---
LICENSES="build/licenses/THIRD_PARTY_LICENSES.txt"
echo "==> ./scripts/generate_license_list.sh ${LICENSES}"
./scripts/generate_license_list.sh "${LICENSES}"

# --- ステージングディレクトリを作り直してDMGへ固める ---
STAGING="build/macos/dmg-staging"
rm -rf "${STAGING}"
mkdir -p "${STAGING}"
cp -R "${APP}" "${STAGING}/"
ln -s /Applications "${STAGING}/Applications"
cp "${LICENSES}" "${STAGING}/THIRD_PARTY_LICENSES.txt"

OUT_DIR="build/macos/dmg"
mkdir -p "${OUT_DIR}"
DMG_PATH="${OUT_DIR}/BubiFM77AV40EX-${VERSION}.dmg"
rm -f "${DMG_PATH}"

echo "==> hdiutil create ${DMG_PATH}"
hdiutil create \
  -volname "BubiFM77AV40EX ${VERSION}" \
  -srcfolder "${STAGING}" \
  -format UDZO \
  -fs HFS+ \
  -ov \
  "${DMG_PATH}"

rm -rf "${STAGING}"

echo "==> built: ${DMG_PATH}"
