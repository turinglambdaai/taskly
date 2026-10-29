# Taskly Product Specification (Contract)

> Cross-platform behavior contract for the native apps (macOS / Windows /
> Linux). Sources of truth: this file + DATA-FORMAT + CLI-SPEC +
> DESIGN-TOKENS + shared/i18n. Platform-native interaction idioms may differ
> (menus, pickers) as long as the behavior contract holds.

## 1. Product

Taskly — a focused personal task manager in the spirit of macOS Reminders,
macOS Reminders neutral palette (DESIGN-TOKENS), bilingual zh/en (runtime
switchable), light/dark. Desktop today; iOS/iPadOS/Android later. Single
SQLite file the user can place in a cloud-synced folder; agent-facing CLI
with the semantics in CLI-SPEC (the CLI runs from source today — the
release packages don't include a standalone CLI binary yet; see the
README's honest gaps).

## 2. Window & layout

- Default 1024×768, min 760×520. Menu bar (or native menu on macOS) +
  status bar + main split: sidebar 280px (min 200, max 420, resizable) +
  task pane.
- Status bar shows a persistent line (search term > view description >
  list name; `Database Not Connected` when closed). Transient messages
  (task added, switched list…) revert to persistent after 3 s.
- **Search lives in the header toolbar** (right side, next to the
  Show Completed toggle — Reminders convention). The quick-add field is
  the task pane's only input, directly under the large view title.
- Sidebar collapse toggle (`‹`/`›`); the task pane takes the full width.

## 3. Sidebar

- 2×2 smart-view tiles, fixed semantic colors (DESIGN-TOKENS), platform
  glyphs (macOS SF Symbols `calendar` / `calendar.badge.clock` / `tray.full`
  / `checkmark.circle`), quiet chip fill with the color on the glyph, count
  top-right: Today `#007AFF` · Planned `#FF3B30` · All `#8E8E93` ·
  Completed `#8E8E93`. Counts: today = due today & incomplete; planned =
  has date & incomplete; all = incomplete; completed = completed.
- "My Lists" collapsible section with a `✚` add button → create-list sheet.
- List row: 20px round swatch (list color, accent fallback) + emoji
  (fallback 📋) + name + pending count (when > 0).
  - Click → select list (persists `last-selected-list-id`).
  - Right-click / double-click → edit-list sheet (rename, icon, color).
  - Deleting the selected list falls back to the All view.
- All interactions inert when no DB is connected.

## 4. Task pane

- Header: view title (search term shows `Search tasks: <kw>`), and a
  Show/Hide Completed toggle (accent text) when connected.
- Quick-add field (connected only), placeholder `+ 添加任务`. Enter commits:
  text first runs through ExtractTimeCommand (trailing `@10am`, `+1d`…),
  target list = selected list else first list (none → error
  `taskCreateListFirst`); new task lands at top; counts refresh.
  The host captures the **concrete list ID at submission**, before any
  asynchronous parsing or persistence. Switching lists while the request
  is running must never change the destination. No list / invalid selected
  list must keep the unsent text rather than silently using another list.
  The Windows packaged acceptance must create a second list, submit a
  task via Enter, verify that it remains in the selected list, and verify
  that it never appears in the first/default list.
  Snapshot rendering is equally view-scoped: responses must be checked
  against the currently selected view/list and completed-visibility flag.
  Results from a previous selection must never appear under the newly
  selected list title. When a database is opened with a restored named
  list, its initial ALL snapshot must not populate that named list; query
  the selected list first.
- Empty states: not connected → 📂 + `taskListEmptyHint`; connected and
  empty → ✓ + actionable `taskListEmptyFirstRun`, which points at quick add
  and includes a harmless example. A successful first task replaces the hint;
  reopening the database must show the persisted row instead of the hint.
- Row order per view (SQL in DATA-FORMAT/CLI-SPEC §list): All & list views
  `id DESC` with completed sinking when shown; Planned by `due_date ASC`;
  Today `id DESC`; Completed unordered.
- Deleting a task from a row or the shared batch action has **no** confirmation;
  the reversible six-second staging window below is the safety mechanism.

## 5. Task row

- 20px circular checkbox: incomplete = hollow ring; complete = ring +
  check in accent; completed text gets strikethrough + tertiary color.
  The checkbox and task title share the **same first-row vertical center**
  on every platform. Due date, time and notes (only when actually present)
  sit beneath the title, not beside or vertically above the checkbox.
  A task with no metadata renders as one clean centered checkbox/title row.
- Meta line under the text when present: the localized due date
  (today/tomorrow/yesterday/`Aug 31`/`8月31日`, plus the time when set) in
  its semantic color (overdue incomplete `#FF3B30`, due today accent,
  otherwise text/secondary; completed always secondary), and a
  single-line-ellipsized notes preview. The checkbox ring takes the task's
  list color (accent fallback); Linux, whose stock CheckButton carries no
  recolorable ring, renders an 8px list-color dot before the row instead
  (platform-native idiom, same information).
- `ⓘ` button (always visible) expands the row's inline editor.
- Edit mode (ⓘ / Return / double-click): the title field receives focus;
  a visible **Save** and **Cancel** pair is always present; Enter saves, Esc
  cancels the complete draft, and clicking another row saves before moving
  focus. Save immediately shows a saving acknowledgement, then a persisted
  success or actionable error. A failed explicit save leaves (or reopens) the
  complete draft for correction and retry. Title, notes, date and time form
  one draft: no field is persisted until the edit commits. A blank edited
  title retains the stored title rather than creating an invalid task.
- Context menu: Toggle Completed, quick reschedule (今天 / 明天 /
  自定日期 / 清除 — the explicit entry points for changing a due
  date), Details, Delete, and Move to List ▸ (other lists,
  `{icon} {name}`) when they exist.

## 5b. Task interactions (Reminders parity)

This section is the three-host contract. Native controls and modifier glyphs
differ, but draft, identity and persistence outcomes do not.

- Hover: quiet row fill (hover token) only, plus the info button
  emphasizing (opacity step). Hover never moves row content or reveals
  new controls — Reminders keeps quick-date buttons in the details
  popover and the context menu, not on the row.
- Selection: click selects; ⌘-click toggles; ⇧-click and ⇧↑/⇧↓ extend a
  range; Esc clears; any click on another row collapses an expanded row.
- Keyboard: ↑/↓ move the selection, Return expands the selected row in
  place, Esc cancels the expanded draft (a second Esc clears selection).
  While a text field has focus, normal editing shortcuts pass through; Enter
  and Esc retain the commit/cancel meanings above.
- Inline expansion (ⓘ / Return / double-click): the row expands in place —
  title (15px semibold borderless), date/time chips (5-minute time steps),
  borderless notes, then visible Save/Cancel actions — edits commit on Save,
  Return or click-away; no modal sheet. Esc and Cancel discard all buffered
  fields. The date
  chip's popover leads with quick dates (今天 / 明天 / 本周末, where
  本周末 is the coming weekend day) above a native calendar. Selecting a date
  updates the draft only; Save/Return/click-away performs the persistence,
  matching the Reminders details-popover discoverability without hiding
  Taskly's explicit transaction boundary.
- Delete: no confirmation from the row; instead the host hides the selected
  rows and stages their original records for about six seconds. 撤销 restores
  the same task IDs and complete metadata because no backend delete has yet
  occurred. Timeout (or starting another delete batch) commits the captured
  IDs. A database switch/disconnect abandons the old batch and must never
  apply those IDs to the new database.
- Completed tasks render under a collapsible "已完成 N" section header
  (chevron + count) whenever completed tasks are displayed.
- Sidebar: double-click a list renames it (opens the edit sheet).
- Quick add: accent + button, focus-highlighted border, live parse-preview chip (typing a schedule shows the parsed date/time before Enter).
- Not in v1.x: swipe gestures, subtasks (Tab indent), multi-drag.

## 6. Interaction lifecycle scenarios

Every declared host runs the same outcome scenarios in packaged native-UI
acceptance. Accessibility mechanics may differ; the stable task identity and
draft/persistence results may not.

| Scenario | Before | Action | Required result |
|---|---|---|---|
| Edit → Escape | stored task `id=N`; editor holds changed title/notes/date/time | press Esc while a field owns focus | editor closes; all fields still equal the stored record for `N` |
| Edit → click away / Return | stored task `id=N`; editor holds a valid draft | select another row, or press Return in title | one update commits the draft to `N`; a refresh preserves it |
| Edit → visible Save | stored task `id=N`; editor holds changed title/notes/date/time | press Save | status announces saving, then success; reopening reads every field from persistence; an optimistic close must restore the complete draft if persistence fails |
| Edit → save failure | stored task `id=N`; editor holds a valid draft | press Save; backend rejects/fails | an actionable error is visible; all buffered fields remain available for correction/retry; stored `N` is unchanged |
| Edit → visible Cancel | stored task `id=N`; editor holds changed title/notes/date/time | press Cancel | editor closes, cancellation is acknowledged, and reopening shows the stored record unchanged |
| Delete → undo | stored rows with IDs and metadata | delete, then undo inside ~6 s | rows return with the original IDs, completion, dates, notes and list ownership |
| Delete → timeout | stored rows with IDs and metadata | delete; let ~6 s expire | backend deletes exactly the captured IDs; later refresh does not restore them |
| Search refresh | global results include task `N` from another list | backend `changed` event / periodic refresh | search remains owner; `N` retains its real list label, selection and in-progress draft |
| Database switch | edit or delete batch belongs to database A | open/close/switch to database B | A's pending callbacks cannot mutate B; selection, drafts and undo state are cleared |

Windows UI Automation, macOS Accessibility and Linux AT-SPI traces cover the
keyboard/focus and identity-preserving undo paths. Core/RVT1 tests cover the
database-session and stale-callback boundary. A host-specific exception must
be written here before it can be accepted; none is declared for these rows.

## 7. Pickers

- Date: the date action opens the platform-native calendar, led by Today /
  Tomorrow / This Weekend; it is bounded 1900-01-01…2100-12-31; Clear removes
  date and time from the draft. Date selection never silently commits the
  surrounding task draft.
- Time: hour 00–23 + minute in 5-minute steps (00…55); current minute
  rounds to nearest 5; Clear → no time.

## 8. Menus / app-level

- File: New Database (Ctrl+Shift+N, save panel, default name `tasks`),
  Open Database (Ctrl+O, *.db), Close Database (confirm), Quit/Exit.
- View: Today / Planned / All / Completed (Ctrl+1…4), New Task
  (Ctrl+N, focuses quick add), Search (Ctrl+F, focuses search), Show
  Completed toggle (Ctrl+Shift+C).
- Tools: Install / Uninstall Command Line Tool.
- Settings: Language (简体中文 / English, runtime switch, persisted in
  config `language`), Theme submenu — 跟随系统 (follow system) / 浅色
  (light) / 深色 (dark), persisted in config `theme`; follow-system tracks
  OS personalization live. Windows reads the persisted language and theme
  before first window activation (no temporary English/light frame); the
  backend settings RPC remains authoritative once connected. macOS follows
  the system appearance at launch and live; its Settings toggle is a
  per-session override. Async persistence
  acknowledgements must **not** overwrite local settings changed since the
  request began (including `last-selected-list-id`, theme and language).
  The locally selected list remains authoritative through overlapping
  preferences saves; the backend result confirms persistence or an error.
  Plus 检查更新… /
  Check for Updates… (manual online-update check; auto-check runs at
  launch and every 4 h — contract: `UPDATE.md`).
- Help: About — `Taskly v<version>` + `© 2026 Taskly Team` +
  `aboutContent` + license line (`aboutLicense`) + link buttons on every
  host: Website (`aboutWebsite` → taskly.jrtx.site), User Manual
  (`aboutManual` → taskly.jrtx.site/manual.html), Changelog
  (`aboutChangelog` → the CHANGELOG on GitHub), and Report an Issue
  (`aboutReportIssue` → the GitHub issue tracker). Below the links, a
  diagnostics block shows the release identity and the data locations —
  app version, platform + architecture, OS version, database path,
  config path — with a `aboutCopyDiagnostics` button that puts the same
  block on the clipboard so a bug report can include it verbatim; the
  copy confirmation is a transient status message. Diagnostics labels
  are English fixed strings (machine-oriented, like the CLI's `--json`).
  macOS and Windows render the fields inside their sheet/dialog; Linux
  builds the same layout on a plain GtkDialog — GtkAboutDialog cannot
  carry multiple links, so the native about dialog is not used.
- All accelerators work window-wide without opening the menu.

## 9. Reminders (all platforms)

- Check every 60 s while a DB is connected; plus one check at startup.
- Due = incomplete ∧ has due_date ∧ `combine(due_date, due_time|00:00) ≤ now`
  (overdue included, however old).
- Each task notified at most once per session (dedupe set, reset when the
  DB changes). Startup: ≤3 overdue → one notification each; >3 → single
  summary `"<N> task(s) overdue"`. Everything seen at startup is marked
  notified.
- The shared Racket application service owns eligibility, summarization and
  the logical database session. It emits a typed `task` or `summary` decision
  and records `emitted → attempted → delivered|failed`; repeated wakeups never
  retry an emitted decision. A database switch invalidates outstanding tokens.
  Native hosts own permission, timers, OS delivery and localized presentation.
  Clock/calendar inputs are injectable in core fixtures, including local
  midnight and DST-boundary cases.
- Notification: title `⏰ 任务到期` (reminderTitle), body
  `<text>\n<reminderDueAt>: <dueDate[ dueTime]>`.
- Never crash: missing notification permission or any transport failure is
  swallowed and disables native delivery for the app session (this crashed on
  macOS once — 0.6.1 regression — never again). The failed handoff is
  acknowledged without creating a duplicate retry. No click-through action
  required. Reminders are process-bound: no host promises background delivery
  after Taskly exits or while the computer sleeps.

## 10. Validation

Task text non-empty ≤1000 chars; list name non-empty ≤100; date year
1900–2100; (search keyword ≤200 — CLI layer). Error messages from i18n.

## 11. i18n

All user-facing strings come from `shared/i18n/{zh,en}.json` (copied into
each app; CI verifies byte-identity). `T(key)`: current language → zh
fallback → key itself. `{0}` placeholders formatted positionally. Default
zh; persisted in config. **Date shapes are not copy**: they follow the app
language through the platform culture/locale formatter (zh-CN / en-US).

## 12. Known v0.6.4 quirks — resolved in native apps

- GUI quick-add stores "now" as dueTime for `+1d` (CLI semantics differ):
  native apps adopt the **CLI semantics** (pure-date intent clears time) in
  the GUI too.
- Completed view has no stable order: native apps sort completed-last by id
  DESC within the view for determinism.
- GUI has no search field (CLI-only search): native macOS/Windows/Linux
  apps **add** a search field (product decision, flagged as an intentional
  delta from 0.6.4).
