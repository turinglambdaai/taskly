#!/usr/bin/env bash
set -euo pipefail

repo="$1"
output="$2"
mkdir -p "$output"

dmg="$(find "$repo/dist" -maxdepth 1 -name 'taskly-*-macos*.dmg' -type f -print -quit)"
[[ -n "$dmg" ]]
temp_base="${RUNNER_TEMP:-${TMPDIR:?TMPDIR is required on macOS}}"
mount="$temp_base/taskly-dmg-mount-$$"
install_root="$output/installed"
application="$install_root/Taskly.app"
mounted=0

cleanup() {
  if [[ "$mounted" -eq 1 ]]; then
    hdiutil detach "$mount" -quiet || true
  fi
}
trap cleanup EXIT

mkdir -p "$mount" "$install_root"
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount" >"$output/dmg-attach.log"
mounted=1
source_app="$(find "$mount" -maxdepth 1 -name '*.app' -type d -print -quit)"
[[ -n "$source_app" ]]
[[ -L "$mount/Applications" ]]
ditto "$source_app" "$application"
executable="$(find "$application/Contents/MacOS" -maxdepth 1 -type f -perm -111 -print -quit)"
[[ -n "$executable" ]]
codesign --verify --deep --strict --verbose=2 "$application" 2>"$output/codesign-verify.log"

set +e
spctl --assess --type execute --verbose=4 "$application" >"$output/gatekeeper.log" 2>&1
gatekeeper_status=$?
set -e

hdiutil detach "$mount" -quiet
mounted=0

artifact_sha="$(shasum -a 256 "$dmg" | awk '{print $1}')"
cat >"$output/installed-app.json" <<EOF
{"platform":"macos","installer":"dmg","artifact":"$dmg","artifactSha256":"$artifact_sha","application":"$application","executable":"$executable","applicationsLink":true,"codesignVerified":true,"gatekeeperAccepted":$([[ "$gatekeeper_status" -eq 0 ]] && echo true || echo false),"packageVerified":true}
EOF
cp "$output/installed-app.json" "$output/package.json"
