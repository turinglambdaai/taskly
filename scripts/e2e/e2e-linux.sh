#!/usr/bin/env bash
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
output="$repo/.rivet/acceptance/linux"
install_record="$output/installed-app.json"
if [[ -f "$install_record" ]]; then
  executable=/opt/taskly/RivetHost
  installed_package=taskly
else
  executable="$(find "$repo/dist" -path '*/taskly-linux-*/RivetHost' -type f -print -quit)"
  installed_package=""
fi
home="$output/home-$$"
first_home="$output/first-run-home-$$"
mkdir -p "$output" "$home/.taskly" "$first_home/.taskly"
[[ -n "$executable" && -x "$executable" ]]

epoch="$(date +%s)"
cat >"$home/.taskly/config.ini" <<EOF
# Taskly acceptance profile
language = en
close-to-tray = 0
last-selected-list-id = 0
last-update-check = $epoch
EOF
cp "$home/.taskly/config.ini" "$first_home/.taskly/config.ini"

# Seed IDs beyond the 32-bit boundary so the GTK acceptance flow exercises
# the exact row-data conversions used by list selection and batch actions.
/usr/bin/python3 - "$home/.taskly/tasks.db" <<'PY'
import sqlite3
import sys

database = sqlite3.connect(sys.argv[1])
database.executescript(
    """
    PRAGMA journal_mode = WAL;
    PRAGMA user_version = 4;
    CREATE TABLE lists (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        icon TEXT,
        color INTEGER,
        created_at TEXT NOT NULL
    );
    CREATE TABLE tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        list_id INTEGER,
        text TEXT NOT NULL,
        due_date TEXT,
        due_time TEXT,
        completed INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        notes TEXT,
        FOREIGN KEY (list_id) REFERENCES lists (id)
    );
    CREATE INDEX idx_tasks_list_id ON tasks(list_id);
    CREATE INDEX idx_tasks_completed ON tasks(completed);
    CREATE INDEX idx_tasks_due_date ON tasks(due_date);
    INSERT INTO lists (id, name, icon, color, created_at) VALUES
      (1, 'Default list', 'D', -16745729, '2026-10-21T00:00:00Z'),
      (4294967301, '64-bit identity list', 'H', -13318311, '2026-10-21T00:00:00Z');
    INSERT INTO tasks
      (id, list_id, text, due_date, due_time, completed, created_at, notes)
    VALUES
      (1, 1, 'Default-list sentinel', NULL, NULL, 0,
       '2026-10-21T00:00:00Z', NULL),
      (4294967302, 4294967301, '64-bit task A', NULL, '09:30', 0,
       '2026-10-21T00:00:00Z', 'metadata A'),
      (4294967303, 4294967301, '64-bit task B', NULL, '10:45', 0,
       '2026-10-21T00:00:00Z', 'metadata B');
    """
)
database.commit()
database.close()
PY

export HOME="$home"
export XDG_RUNTIME_DIR="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/taskly-acceptance-runtime-$$"
# The Weston 13 headless backend used by Ubuntu 24.04 exposes no
# wl_seat. Without a real keyboard seat it cannot verify focus or key input.
# Use a native X11 display and a real window manager for keyboard AT-SPI,
# then separately boot-check the packaged binary under headless Wayland.
export DISPLAY=":$((110 + BASHPID % 400))"
export GDK_BACKEND=x11
unset WAYLAND_DISPLAY
export GTK_A11Y=atspi
# Only native acceptance turns on focus-chain diagnostics; shipped apps stay quiet.
export TASKLY_FOCUS_DEBUG=1
export NO_AT_BRIDGE=0
mkdir -p "$XDG_RUNTIME_DIR"
chmod 700 "$XDG_RUNTIME_DIR"

Xvfb "$DISPLAY" -screen 0 1280x800x24 -nolisten tcp >"$output/xvfb.log" 2>&1 &
display_pid=$!
openbox_pid=""
wayland_pid=""
wayland_app_pid=""
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
  [[ -n "$wayland_app_pid" ]] && kill -TERM "$wayland_app_pid" 2>/dev/null || true
  [[ -n "$wayland_pid" ]] && kill -TERM "$wayland_pid" 2>/dev/null || true
  [[ -n "$openbox_pid" ]] && kill -TERM "$openbox_pid" 2>/dev/null || true
  kill -TERM "$display_pid" 2>/dev/null || true
  wait "$app_pid" "$atspi_pid" "$wayland_app_pid" "$wayland_pid" "$openbox_pid" "$display_pid" 2>/dev/null || true
  if [[ -n "$installed_package" ]]; then
    data_preserved=false
    [[ -f "$home/.taskly/tasks.db" && -f "$first_home/.taskly/tasks.db" ]] && data_preserved=true
    sudo dpkg -r "$installed_package" >"$output/deb-uninstall.log" 2>&1 || status=1
    binary_removed=false
    desktop_removed=false
    [[ ! -e /opt/taskly/RivetHost ]] && binary_removed=true
    [[ ! -e /usr/share/applications/taskly.desktop ]] && desktop_removed=true
    printf '{"installer":"deb","binaryRemoved":%s,"desktopEntryRemoved":%s,"dataPreserved":%s}\n' \
      "$binary_removed" "$desktop_removed" "$data_preserved" >"$output/install-lifecycle.json"
    if [[ "$binary_removed" != true || "$desktop_removed" != true ]]; then status=1; fi
    if [[ "$status" -eq 0 && "$data_preserved" != true ]]; then status=1; fi
  fi
  exit "$status"
}
trap cleanup EXIT

for _ in $(seq 1 100); do
  xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && break
  kill -0 "$display_pid" 2>/dev/null
  sleep 0.05
done
xdpyinfo -display "$DISPLAY" >"$output/x11-display.log"
openbox --sm-disable >"$output/openbox.log" 2>&1 &
openbox_pid=$!
for _ in $(seq 1 100); do
  if xprop -root _NET_SUPPORTING_WM_CHECK 2>/dev/null | grep -q 'window id'; then
    break
  fi
  kill -0 "$openbox_pid" 2>/dev/null
  sleep 0.05
done
xprop -root _NET_SUPPORTING_WM_CHECK | grep -q 'window id'

# Keep a separate packaged Wayland boot smoke. It does not pretend to cover
# keyboard focus; only X11 with a real input seat runs the AT-SPI journey.
wayland_runtime="$output/wayland-runtime-$BASHPID"
wayland_home="$output/wayland-home-$BASHPID"
mkdir -p "$wayland_runtime" "$wayland_home"
chmod 700 "$wayland_runtime"
wayland_socket=wayland-taskly-smoke
XDG_RUNTIME_DIR="$wayland_runtime" weston --backend=headless-backend.so \
  --socket="$wayland_socket" --idle-time=0 --log="$output/weston.log" &
wayland_pid=$!
for _ in $(seq 1 100); do
  [[ -S "$wayland_runtime/$wayland_socket" ]] && break
  kill -0 "$wayland_pid" 2>/dev/null
  sleep 0.05
done
[[ -S "$wayland_runtime/$wayland_socket" ]]
GDK_BACKEND=wayland WAYLAND_DISPLAY="$wayland_socket" \
  XDG_RUNTIME_DIR="$wayland_runtime" HOME="$wayland_home" \
  "$executable" >"$output/wayland-smoke.log" 2>&1 &
wayland_app_pid=$!
sleep 4
kill -0 "$wayland_app_pid"
stop_bounded "$wayland_app_pid"
wait "$wayland_app_pid" 2>/dev/null || true
wayland_app_pid=""
stop_bounded "$wayland_pid"
wait "$wayland_pid" 2>/dev/null || true
wayland_pid=""

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

export HOME="$first_home"
"$executable" >"$output/first-run-application.log" 2>&1 &
app_pid=$!
/usr/bin/python3 "$repo/scripts/e2e/linux-atspi.py" --output "$output" --mode first-run
stop_bounded "$app_pid"
wait "$app_pid" 2>/dev/null || true
app_pid=""

"$executable" >"$output/first-run-restart.log" 2>&1 &
app_pid=$!
/usr/bin/python3 "$repo/scripts/e2e/linux-atspi.py" --output "$output" --mode verify-first-run
stop_bounded "$app_pid"
wait "$app_pid" 2>/dev/null || true
app_pid=""

/usr/bin/python3 - "$first_home/.taskly/tasks.db" <<'PY'
import datetime
import sqlite3
import sys

database = sqlite3.connect(sys.argv[1])
expected = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
row = database.execute(
    "SELECT due_date FROM tasks WHERE text = 'First-run persistence task'"
).fetchone()
assert row == (expected,), row
database.close()
PY

export HOME="$home"
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

# UI actions must have targeted the full-width IDs and kept undo metadata.
/usr/bin/python3 - "$home/.taskly/tasks.db" <<'PY'
import datetime
import sqlite3
import sys

database = sqlite3.connect(sys.argv[1])
tomorrow = (datetime.date.today() + datetime.timedelta(days=1)).isoformat()
rows = database.execute(
    "SELECT id, list_id, text, due_date, due_time, completed, notes "
    "FROM tasks WHERE id IN (4294967302, 4294967303) ORDER BY id"
).fetchall()
assert rows == [
    (4294967302, 4294967301, '64-bit task A', tomorrow, None, 0, 'metadata A'),
    (4294967303, 4294967301, 'Saved inline draft', tomorrow, None, 0, 'metadata B'),
], rows
created = database.execute(
    "SELECT list_id, completed FROM tasks WHERE text = 'Acceptance task'"
).fetchone()
assert created == (4294967301, 0), created
database.close()
PY

kill -TERM "$atspi_pid" "$openbox_pid" "$display_pid" 2>/dev/null || true
wait "$atspi_pid" "$openbox_pid" "$display_pid" 2>/dev/null || true
atspi_pid=""
openbox_pid=""
display_pid=""
