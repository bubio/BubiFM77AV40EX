#!/usr/bin/env bash
# Linux配布物（deb / rpm / AppImage）を、scripts/build_linux.sh が作った
# 同じbundleから生成する（development_plan.md M6、design.md 15.2）。
# ローカルとCIで同じ手順を使う。
#
#   usage: scripts/package_linux.sh [deb] [rpm] [appimage]
#          引数なしなら3形式すべてを作る。
#
# 必要なコマンド: dpkg-deb（deb）、rpmbuild（rpm）、ImageMagick（アイコン）、
# AppImageはappimagetool。appimagetoolは環境変数 APPIMAGETOOL で指定でき、
# 未指定ならcontinuousリリースを build/ 配下へ取得する。
set -euo pipefail

cd "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FORMATS=("$@")
[ "${#FORMATS[@]}" -eq 0 ] && FORMATS=(deb rpm appimage)

APP_NAME="BubiFM77AV40EX"
APP_ID="com.bubio.BubiFM77AV40EX"
PKG_NAME="bubifm77av40ex"
INSTALL_DIR="/opt/${PKG_NAME}"
SUMMARY="FM77AV40EX emulator"

case "$(uname -m)" in
  x86_64) FLUTTER_ARCH="x64"; DEB_ARCH="amd64"; RPM_ARCH="x86_64" ;;
  aarch64 | arm64) FLUTTER_ARCH="arm64"; DEB_ARCH="arm64"; RPM_ARCH="aarch64" ;;
  *) echo "error: 未対応のアーキテクチャです: $(uname -m)" >&2; exit 1 ;;
esac

BUNDLE="build/linux/${FLUTTER_ARCH}/release/bundle"
if [ ! -x "${BUNDLE}/${APP_NAME}" ]; then
  echo "error: ${BUNDLE} がありません。先に scripts/build_linux.sh を実行してください。" >&2
  exit 1
fi

VERSION="$(grep -m1 '^version:' pubspec.yaml | sed 's/^version:[[:space:]]*//' | cut -d '+' -f1)"
if [ -z "${VERSION}" ]; then
  echo "error: pubspec.yamlからバージョンを取得できません" >&2
  exit 1
fi
# SemVerのプレリリース区切り "-" は、deb/rpmでは "~" にしないと
# 正式版より新しい版として並ぶ。
PKG_VERSION="${VERSION//-/\~}"

WORK="build/linux/package"
OUT_DIR="build/linux/dist"
rm -rf "${WORK}" "${OUT_DIR}"
mkdir -p "${WORK}" "${OUT_DIR}"

if command -v magick >/dev/null 2>&1; then
  IMAGEMAGICK=(magick)
elif command -v convert >/dev/null 2>&1; then
  IMAGEMAGICK=(convert)
else
  echo "error: ImageMagick（magick または convert）が必要です" >&2
  exit 1
fi

LICENSES="build/licenses/THIRD_PARTY_LICENSES.txt"
echo "==> ./scripts/generate_license_list.sh ${LICENSES}"
./scripts/generate_license_list.sh "${LICENSES}"

# --- deb/rpmが共有するインストールツリー ---
#
# Flutterのbundleは実行ファイルと lib/・data/ の相対配置に依存するため、
# /opt 配下へまとめて置き、/usr/bin からはシンボリックリンクで指す。
ROOT="${WORK}/root"
mkdir -p "${ROOT}${INSTALL_DIR}" "${ROOT}/usr/bin" \
  "${ROOT}/usr/share/applications" "${ROOT}/usr/share/doc/${PKG_NAME}"
cp -a "${BUNDLE}/." "${ROOT}${INSTALL_DIR}/"
ln -s "${INSTALL_DIR}/${APP_NAME}" "${ROOT}/usr/bin/${PKG_NAME}"
cp LICENSE "${ROOT}/usr/share/doc/${PKG_NAME}/LICENSE"
cp "${LICENSES}" "${ROOT}/usr/share/doc/${PKG_NAME}/THIRD_PARTY_LICENSES.txt"

# アイコンは正本PNGから規定サイズを作る（design.md 15.3）。
for size in 16 32 48 64 128 256 512; do
  dir="${ROOT}/usr/share/icons/hicolor/${size}x${size}/apps"
  mkdir -p "${dir}"
  "${IMAGEMAGICK[@]}" assets/branding/app_icon.png -resize "${size}x${size}" \
    "${dir}/${APP_ID}.png"
done

# desktop entryの名前はGTKのapplication IDと揃える（Waylandのapp_idと一致させる）。
write_desktop_entry() {
  cat > "$1" <<DESKTOP
[Desktop Entry]
Type=Application
Name=${APP_NAME}
Comment=${SUMMARY}
Comment[ja]=FM77AV40EX エミュレーター
Exec=$2
Icon=${APP_ID}
Terminal=false
Categories=Game;Emulator;
DESKTOP
}
write_desktop_entry "${ROOT}/usr/share/applications/${APP_ID}.desktop" "${PKG_NAME}"

if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "${ROOT}/usr/share/applications/${APP_ID}.desktop"
fi

build_deb() {
  local deb_root="${WORK}/deb"
  cp -a "${ROOT}" "${deb_root}"
  mkdir -p "${deb_root}/DEBIAN"

  local installed_size
  installed_size="$(du -sk "${deb_root}" | cut -f1)"

  # GTKとALSAはUbuntu 24.04で t64 付きへ改名された。旧名も許す。
  # 音声はminiaudioが実行時にdlopenするため、共有ライブラリの依存解析には
  # 現れない。明示的に書く。
  cat > "${deb_root}/DEBIAN/control" <<CONTROL
Package: ${PKG_NAME}
Version: ${PKG_VERSION}
Architecture: ${DEB_ARCH}
Maintainer: bubio <bubio66@gmail.com>
Installed-Size: ${installed_size}
Depends: libgtk-3-0t64 | libgtk-3-0, libasound2t64 | libasound2
Recommends: fonts-noto-cjk
Section: otherosfs
Priority: optional
Homepage: https://github.com/bubio/BubiFM77AV40EX
Description: ${SUMMARY}
 FM77AV40EX emulator front-end built on the Common Source Code Project core.
CONTROL

  local out="${OUT_DIR}/${APP_NAME}-${VERSION}-linux-${DEB_ARCH}.deb"
  echo "==> dpkg-deb --build ${out}"
  dpkg-deb --build --root-owner-group "${deb_root}" "${out}"
}

build_rpm() {
  local top
  top="$(pwd)/${WORK}/rpmbuild"
  mkdir -p "${top}/SPECS"

  # 依存はdebと同じ理由で手書きにする。自動解析はbundle内のFlutter
  # ライブラリをシステムへ要求してしまうため止める。
  cat > "${top}/SPECS/${PKG_NAME}.spec" <<SPEC
%global debug_package %{nil}
%global _build_id_links none
%global __os_install_post %{nil}

Name: ${PKG_NAME}
Version: ${PKG_VERSION}
Release: 1
Summary: ${SUMMARY}
License: GPL-2.0-only
URL: https://github.com/bubio/BubiFM77AV40EX
AutoReqProv: no
Requires: gtk3
Requires: alsa-lib
Recommends: google-noto-sans-cjk-fonts

%description
FM77AV40EX emulator front-end built on the Common Source Code Project core.

%install
cp -a "$(pwd)/${ROOT}/." "%{buildroot}/"

%files
${INSTALL_DIR}
/usr/bin/${PKG_NAME}
/usr/share/applications/${APP_ID}.desktop
/usr/share/icons/hicolor/*/apps/${APP_ID}.png
%doc /usr/share/doc/${PKG_NAME}
SPEC

  echo "==> rpmbuild -bb (${RPM_ARCH})"
  rpmbuild -bb --target "${RPM_ARCH}" --define "_topdir ${top}" \
    "${top}/SPECS/${PKG_NAME}.spec"

  local built
  built="$(find "${top}/RPMS" -name '*.rpm' -print -quit)"
  [ -n "${built}" ] || { echo "error: rpmが生成されませんでした" >&2; exit 1; }
  cp "${built}" "${OUT_DIR}/${APP_NAME}-${VERSION}-linux-${RPM_ARCH}.rpm"
}

build_appimage() {
  local appdir="${WORK}/AppDir"
  mkdir -p "${appdir}/app"
  cp -a "${BUNDLE}/." "${appdir}/app/"
  cp -a "${ROOT}/usr" "${appdir}/usr"
  rm -f "${appdir}/usr/bin/${PKG_NAME}"

  cat > "${appdir}/AppRun" <<'APPRUN'
#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
exec "${HERE}/app/BubiFM77AV40EX" "$@"
APPRUN
  chmod +x "${appdir}/AppRun"

  write_desktop_entry "${appdir}/${APP_ID}.desktop" "${APP_NAME}"
  cp "${ROOT}/usr/share/icons/hicolor/256x256/apps/${APP_ID}.png" "${appdir}/${APP_ID}.png"
  ln -s "${APP_ID}.png" "${appdir}/.DirIcon"

  local tool="${APPIMAGETOOL:-}"
  if [ -z "${tool}" ]; then
    tool="build/linux/appimagetool-${RPM_ARCH}.AppImage"
    if [ ! -x "${tool}" ]; then
      echo "==> appimagetool を取得する"
      curl -fsSL -o "${tool}" \
        "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${RPM_ARCH}.AppImage"
      chmod +x "${tool}"
    fi
  fi

  local out="${OUT_DIR}/${APP_NAME}-${VERSION}-linux-${RPM_ARCH}.AppImage"
  echo "==> appimagetool ${out}"
  # FUSEのないCIランナーでも動くよう、AppImage自身を展開して実行させる。
  ARCH="${RPM_ARCH}" APPIMAGE_EXTRACT_AND_RUN=1 "${tool}" --no-appstream "${appdir}" "${out}"
}

for format in "${FORMATS[@]}"; do
  case "${format}" in
    deb) build_deb ;;
    rpm) build_rpm ;;
    appimage) build_appimage ;;
    *) echo "error: 未対応の形式です: ${format}" >&2; exit 2 ;;
  esac
done

echo "==> packages:"
ls -1 "${OUT_DIR}"
