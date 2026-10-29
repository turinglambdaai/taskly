#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
output="$repo/.rivet/acceptance/macos"
install_record="$output/installed-app.json"
if [[ -f "$install_record" ]]; then
  app="$(plutil -extract executable raw -o - "$install_record")"
  installed_application="$(plutil -extract application raw -o - "$install_record")"
else
  app="$repo/dist/taskly.app/Contents/MacOS/taskly"
  installed_application=""
fi
driver="$output/macos-ax"
home="$output/home-$$"
mkdir -p "$output" "$home/.taskly"
[[ -x "$app" ]]

epoch="$(date +%s)"
cat >"$home/.taskly/config.ini" <<EOF
# Taskly acceptance profile
language = en
close-to-tray = 0
last-selected-list-id = 0
last-update-check = $epoch
EOF

swiftc "$repo/scripts/e2e/macos-ax.swift" -o "$driver" \
  -framework AppKit -framework ApplicationServices

HOME="$home" "$app" >"$output/application.log" 2>&1 &
app_pid=$!

stop_bounded() {
  local pid="$1"
  kill -TERM "$pid" 2>/dev/null || true
  for _ in $(seq 1 200); do
    kill -0 "$pid" 2>/dev/null || return 0
    sleep 0.05
  done
  kill -KILL "$pid" 2>/dev/null || true
  return 1
}

cleanup() {
  local status=$?
  trap - EXIT
  if kill -0 "$app_pid" 2>/dev/null; then
    stop_bounded "$app_pid" || true
    wait "$app_pid" 2>/dev/null || true
  fi
  if [[ -n "$installed_application" ]]; then
    data_preserved=false
    [[ -f "$home/.taskly/tasks.db" ]] && data_preserved=true
    rm -rf "$installed_application"
    application_removed=false
    [[ ! -e "$installed_application" ]] && application_removed=true
    printf '{"installer":"dmg","applicationRemoved":%s,"dataPreserved":%s}\n' \
      "$application_removed" "$data_preserved" >"$output/install-lifecycle.json"
    if [[ "$status" -eq 0 && "$data_preserved" != true ]]; then status=1; fi
    if [[ "$application_removed" != true ]]; then status=1; fi
  fi
  exit "$status"
}
trap cleanup EXIT

"$driver" --pid "$app_pid" --output "$output"
for _ in $(seq 1 200); do
  kill -0 "$app_pid" 2>/dev/null || break
  sleep 0.05
done
if kill -0 "$app_pid" 2>/dev/null; then
  echo "Taskly did not exit after the native termination request" >&2
  exit 1
fi
wait "$app_pid"
app_pid=""

HOME="$home" "$app" >"$output/application-restart.log" 2>&1 &
app_pid=$!
"$driver" --pid "$app_pid" --output "$output" --verify-restart
wait "$app_pid"
app_pid=""
