# Taskly CLI Specification (Contract)

> Stable agent-facing interface. Every platform binary is dual-mode:
> **any** argument at launch routes to the CLI (the GUI toolkit is never
> initialized); no arguments opens the GUI. Command output and exit codes
> are identical across platforms — enforced by golden-output tests in CI.

```
taskly <subcommand> [options] [--json] [--db PATH] [--quiet]
```

- `--json` machine-readable output (stdout only; errors as JSON on stderr)
- `--db PATH` overrides DB resolution
- `--quiet` / `-q` minimal output (usually just the id)
- DB resolution: `--db` → config `last-db-path` → `~/.taskly/tasks.db`;
  unopenable → error, exit 4.
- Response-file expansion is disabled (`@10am` must never read a file).

## Exit codes

| Code | Meaning | Triggers |
|---|---|---|
| 0 | success (including `rm` of an already-missing id) | |
| 1 | generic error | unknown exceptions; install/uninstall failures |
| 2 | validation failure | bad `--view` / `--status` / `--color`; unparseable `--due`; text/name too long or empty |
| 3 | not found | `--list` name miss; `add` with no lists; `update`/`done`/`undone` unknown id |
| 4 | database error | cannot open; SQLite error |

Error JSON on **stderr**, 2-space indented, always:
`{"ok": false, "error": "<message>", "exitCode": <code>}`

Success JSON on **stdout**, 2-space indented, null fields omitted
(`WhenWritingNull`), fixed field order.

## Task / list JSON shapes

```json
{ "id": 1, "listId": 1, "listName": "工作", "text": "买牛奶", "completed": false,
  "dueDate": "2026-09-16", "dueTime": "10:00", "notes": null, "createdAt": "..." }
{ "id": 1, "name": "工作", "icon": "📋", "color": -4104388, "pendingCount": 3 }
```

Human-readable (non-`--json`) task row: `%5d  [x| ]  text  🗓 dueDate[ dueTime]`;
empty result prints `(no tasks)` (suppressed when `--quiet`).
List row: `%5d  icon name  (pendingCount)`.

## Subcommands

### list
Default: all incomplete.
- `--list ID|NAME` — numeric → id; otherwise **case-sensitive exact** name
  match; miss → exit 3 with `List not found by name: "<list>"`. Takes
  precedence over `--view` when both given.
- `--view today|planned|scheduled|all|completed` (case-insensitive;
  `scheduled` = `planned`; default `all`; anything else → exit 2).
- `--status all|incomplete|open|pending|completed|done` (default
  `incomplete`; `all` and `completed` **both** map to "include completed,
  completed sinks to bottom"; default/others → incomplete only).
- `--limit N` (default 1000).
- `completed` view always `completed = 1`, no ORDER BY.
- Sorting: today `id DESC`; planned `due_date ASC`; all/list `id DESC`
  (completed ASC first when included).

### lists
All lists with `pendingCount` (`COUNT(*) WHERE list_id=? AND completed=0`).

### add "<text>"
- `--list ID|NAME` (default: first list; none exists → exit 3,
  `No lists exist yet. Create one with `taskly mklist` first.`)
- `--due EXPR` (below), `--time HH:mm` (explicit `--time` overrides a time
  carried by `--due`), `--notes "..."`.
- `createdAt` = local ISO-8601 round-trip now. Text validation → exit 2.
- Output: task JSON / human row / quiet → id.

### update <ID>
Read-modify-write; unspecified fields unchanged. `--text --due --clear-due
--time --clear-time --list --notes --clear-notes`.
`--due` overwrites `dueTime` only when the expression carries a time (a pure
date keeps the existing time); `--clear-due` clears the date only. Unknown
id → exit 3. Outputs the updated task.

### done <ID> / undone <ID>
Idempotent `completed=1/0` (affected rows == 0 → exit 3). `--json` prints
the task; `--json --quiet` prints `{"ok":true,"id":N,"completed":bool}`.

### rm <ID>
`--json` prints `{"ok":true,"id":N,"deleted":bool}` regardless of `--quiet`;
exit 0 either way. Non-json: `Deleted task N` / `Task N did not exist`.

### search "<keyword>"
`text LIKE '%kw%'` — task text only, completed included, unsorted,
`--limit` default 100. Empty keyword → empty array.

### mklist "<name>"
`--icon <emoji>` `--color #RRGGBB|AARRGGBB|<int>`. Name validation → exit 2.
Color parsing: plain int → as-is; `#RRGGBB` → `0xFF000000|RGB`; 8-digit hex
→ as-is; anything else → exit 2. Null icon/color get defaults (📋 / Crail).
Output: list JSON / list row / quiet → id.

### rmlist <ID>
Cascade-delete tasks then the list; output like `rm` (`Deleted list N (and
its tasks)`); exit 0 either way.

### install-cli / uninstall-cli
- macOS/Linux: shell wrapper `#!/bin/sh\nexec "<exe>" "$@"` at
  `~/.local/bin/taskly` (chmod +x); if `~/.local/bin` is not on PATH, append
  an idempotent `# Added by Taskly` block to `~/.zshrc` (macOS) /
  `~/.bashrc` (Linux) and report NeedsShellRestart.
- Windows: copy self to `%LOCALAPPDATA%\Programs\Taskly\taskly.exe`, write
  `taskly.cmd` shim, add the dir to `HKCU\Environment\Path` (idempotent,
  REG_EXPAND_SZ) and broadcast `WM_SETTINGCHANGE`.
- Uninstall removes the artifacts; when nothing is installed, print
  `taskly command was not installed (nothing to remove).` to stderr and
  exit 1.

## `--due` expression grammar (ParseDue)

Pre-map bare words (case-insensitive): `today` → `+0d`, `tomorrow`/`tmw` →
`+1d`, `tonight` → `@20:00`.

Then DateParser:
1. Relative `+N{m|h|d|w|M}` — regex `^(\d*)([mhdwM])$`, digits optional
   (default 1), **case-sensitive** (`m` minutes, `M` month = 30 days), from now.
2. `@time`: `now` | `H` | `H:MM` | `Ham` | `Hpm` | `H:MMam` | `H:MMpm`
   (am/pm any case; 12am→0, pm<12→+12; hour 0–23, min 0–59). Optional
   trailing modifier: `tomorrow`/`tmw`, or `sun..sat` = next such weekday
   (if today or past → next week). No modifier + time already past → tomorrow.
3. Absolute: `yyyy-MM-dd`, `yyyy/MM/dd`, `MM/dd/yyyy`, `dd/MM/yyyy` (tried in
   this order), year in [1900, 2100]; normalized to `yyyy-MM-dd`.
4. Relative results are full `yyyy-MM-dd HH:mm:ss`; absolute are `yyyy-MM-dd`.

Pure-date intent (`today/tomorrow/tmw`, `+Nd/+Nw/+NM`, a 10-char absolute
result) **clears dueTime**; `+Nm`/`+Nh`/`@…` keep it.

Unparseable → exit 2:
`Cannot parse date/time: "<due>". Supported: +10m, +2h, +1d, +1w, @10am, @10:30pm, today, tomorrow, yyyy-MM-dd`
