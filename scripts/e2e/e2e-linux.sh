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
    (4294967303, 4294967301, '64-bit task B', tomorrow, None, 0, 'metadata B'),
], rows
created = database.execute(
    "SELECT list_id, completed FROM tasks WHERE text = 'Acceptance task'"
).fetchone()
assert created == (4294967301, 0), created
database.close()
PY

kill -TERM "$atspi_pid" "$weston_pid" 2>/dev/null || true
wait "$atspi_pid" "$weston_pid" 2>/dev/null || true
atspi_pid=""
weston_pid=""
