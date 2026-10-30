#!/usr/bin/env bash
set -euo pipefail

repo="$1"
output="$2"
mkdir -p "$output"

deb="$(find "$repo/dist" -maxdepth 1 -name 'taskly-*-linux-amd64.deb' -type f -print -quit)"
rpm="$(find "$repo/dist" -maxdepth 1 -name 'taskly-*-linux-x86_64.rpm' -type f -print -quit)"
appimage="$(find "$repo/dist" -maxdepth 1 -name 'taskly-*-linux-x86_64.AppImage' -type f -print -quit)"
[[ -n "$deb" && -n "$rpm" && -n "$appimage" ]]

installed=0
prepared=0
cleanup() {
  if [[ "$installed" -eq 1 && "$prepared" -eq 0 ]]; then
    sudo dpkg -r taskly >"$output/deb-uninstall-on-failure.log" 2>&1 || true
  fi
}
trap cleanup EXIT

dpkg-deb --info "$deb" >"$output/deb-info.log"
rpm -qp --info "$rpm" >"$output/rpm-info.log"
file "$appimage" >"$output/appimage-file.log"
appimage_extract="$output/appimage-extract"
mkdir -p "$appimage_extract"
(
  cd "$appimage_extract"
  chmod +x "$appimage"
  "$appimage" --appimage-extract >"$output/appimage-extract.log"
)
[[ -x "$appimage_extract/squashfs-root/AppRun" ]]
find "$appimage_extract/squashfs-root" -maxdepth 2 -name '*.desktop' -type f -print -quit |
  grep -q .
sudo dpkg -i "$deb" >"$output/deb-install.log" 2>&1
installed=1

executable=/opt/taskly/RivetHost
desktop=/usr/share/applications/taskly.desktop
icon=/usr/share/pixmaps/taskly.png
[[ -x "$executable" && -f "$desktop" && -f "$icon" ]]
desktop-file-validate "$desktop"
grep -Fqx 'Exec=/opt/taskly/RivetHost' "$desktop"
grep -Fqx 'Terminal=false' "$desktop"
dpkg-query -W -f='${Status} ${Version}\n' taskly >"$output/dpkg-query.log"

artifact_sha="$(sha256sum "$deb" | awk '{print $1}')"
cat >"$output/installed-app.json" <<EOF
{"platform":"linux","installer":"deb","artifact":"$deb","artifactSha256":"$artifact_sha","executable":"$executable","desktopEntry":"$desktop","icon":"$icon","rpmMetadataVerified":true,"appImageStructureVerified":true,"packageVerified":true}
EOF
cp "$output/installed-app.json" "$output/package.json"
prepared=1
