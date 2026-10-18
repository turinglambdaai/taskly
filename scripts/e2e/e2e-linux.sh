#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
output="$repo/.rivet/acceptance/linux"
executable="$(find "$repo/dist" -path '*/taskly-linux-*/RivetHost' -type f -print -quit)"
home="$output/home-$$"
mkdir -p "$output" "$home/.taskly"
[[ -n "$executable" && -x "$executable" ]]

epoch="$(date +%s)"
cat >"$home/.taskly/config.ini" <<EOF
# Taskly acceptance profile
language = en
close-to-tray = 0
last-selected-list-id = 0
last-update-check = $epoch
EOF

export HOME="$home"
export XDG_RUNTIME_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/taskly-acceptance-runtime-$$"
export WAYLAND_DISPLAY=wayland-taskly-acceptance
export GDK_BACKEND=wayland
export GTK_A11Y=atspi
export NO_AT_BRIDGE=0
unset DISPLAY
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

weston --backend=headless-backend.so --socket="$WAYLAND_DISPLAY" --idle-time=0 \
  --debug --log="$output/weston.log" &
weston_pid=$!
app_pid=""
atspi_pid=""

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
  [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null && stop_bounded "$app_pid" || true
  [[ -n "$atspi_pid" ]] && kill -0 "$atspi_pid" 2>/dev/null && kill -TERM "$atspi_pid" || true
  kill -TERM "$weston_pid" 2>/dev/null || true
  wait "$app_pid" "$atspi_pid" "$weston_pid" 2>/dev/null || true
  exit "$status"
}
trap cleanup EXIT

for _ in $(seq 1 100); do
  [[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]] && break
  kill -0 "$weston_pid" 2>/dev/null
  sleep 0.05
done
[[ -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]]

launcher="$(command -v at-spi-bus-launcher || true)"
[[ -n "$launcher" ]] || launcher=/usr/libexec/at-spi-bus-launcher
"$launcher" --launch-immediately >"$output/at-spi-bus.log" 2>&1 &
atspi_pid=$!
for _ in $(seq 1 100); do
  gdbus call --session --dest org.a11y.Bus --object-path /org/a11y/bus \
    --method org.a11y.Bus.GetAddress >/dev/null 2>&1 && break
  kill -0 "$atspi_pid" 2>/dev/null
  sleep 0.05
done
export AT_SPI_BUS_ADDRESS="$(gdbus call --session --dest org.a11y.Bus \
  --object-path /org/a11y/bus --method org.a11y.Bus.GetAddress |
  sed -E "s/^\('([^']+)',\)$/\1/")"

"$executable" >"$output/application.log" 2>&1 &
app_pid=$!
/usr/bin/python3 "$repo/scripts/e2e/linux-atspi.py" --output "$output"

stop_bounded "$app_pid"
set +e
wait "$app_pid"
app_status=$?
set -e
app_pid=""
[[ "$app_status" -eq 0 || "$app_status" -eq 143 ]]

trap - EXIT
kill -TERM "$atspi_pid" "$weston_pid" 2>/dev/null || true
wait "$atspi_pid" "$weston_pid" 2>/dev/null || true
