# Taskly Product Specification (Contract)

> Cross-platform behavior contract for the native apps (macOS / Windows /
> Linux). Sources of truth: this file + DATA-FORMAT + CLI-SPEC +
> DESIGN-TOKENS + shared/i18n. Platform-native interaction idioms may differ
> (menus, pickers) as long as the behavior contract holds.

## 1. Product

Taskly — a focused personal task manager in the spirit of macOS Reminders,
Anthropic warm palette, bilingual zh/en (runtime switchable), light/dark.
Desktop today; iOS/iPadOS/Android later. Single SQLite file the user can
place in a cloud-synced folder; agent-facing CLI in the same binary.

## 2. Window & layout

- Default 1024×768, min 760×520. Menu bar (or native menu on macOS) +
  status bar + main split: sidebar 280px (min 200, max 420, resizable) +
  task pane.
- Status bar shows a persistent line (search term > view description >
  list name; `Database Not Connected` when closed). Transient messages
  (task added, switched list…) revert to persistent after 3 s.
- Sidebar collapse toggle (`‹`/`›`); the task pane takes the full width.

## 3. Sidebar

- 2×2 smart-view tiles, fixed semantic colors, white text, count top-right:
  Today `🗓` #C15F3C · Planned `📅` #B5543A · All `≡` #8E887E ·
  Completed `✓` #6B8E5A. Counts: today = due today & incomplete; planned =
  has date & incomplete; all = incomplete; completed = completed.
- "My Lists" collapsible section with a `✚` add button → create-list sheet.
- List row: 32px round swatch (list color, accent fallback) + emoji
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
- Empty states: not connected → 📂 + `taskListEmptyHint`; connected and
  empty → ✓ + `taskListEmpty`.
- Row order per view (SQL in DATA-FORMAT/CLI-SPEC §list): All & list views
  `id DESC` with completed sinking when shown; Planned by `due_date ASC`;
  Today `id DESC`; Completed unordered.
- Deleting a task from the row context menu has **no** confirmation;
  deletion from the detail dialog **does**.

## 4b. Calendar view

A time-line view of dated tasks in the spirit of Things 3 "Upcoming": a
compact month grid on top, tasks grouped by day below. Not a drag-and-drop
day planner — the calendar is for *seeing* when work lands and jumping to it;
editing stays in the row/dialog (§5, §6).

- Entry: a fifth, full-width sidebar tile under the 2×2 grid (8 px gap,
  56 px tall, radius 12, fill `tile/calendar` `#5856D6`, platform monochrome
  calendar-day glyph, white label `navCalendar`, no count badge).
- Clicking the tile (or otherwise selecting the calendar view) sets the
  displayed month to the current month and the selected date to today.
- Month grid: 7 columns, weekday short names from `calWeekdayShort1..7`;
  week starts Monday for zh, Sunday for en (index 1 = Monday in both key
  sets; en rendering reorders Sunday to the front). Always 6 rows; leading
  and trailing days from adjacent months render in the tertiary text color
  and stay clickable.
- Day dots: a day cell with N incomplete dated tasks (any lists) shows
  min(N, 3) accent dots under the day number; completed tasks do not count.
- Month navigation: `‹` / `›` step one month; the `calTodayButton` returns
  to the current month and today. Changing months selects that month's 1st.
- Time line below the grid, in one scrollable list:
  1. An **overdue** group first (title `calOverdue`) — incomplete tasks with
     a due date before today, any month (with Show Completed on, completed
     tasks from before today appear here too).
  2. Then one group per day of the displayed month that has tasks (per the
     same show-completed toggle): the month is queried as one range and
     grouped client-side.
- Group header: `calDayHeader` formatted (`9月26日 · 周五` / `Friday,
  September 26`); the weekday slot shows the relative word (navToday /
  dateTomorrow / dateYesterday) when the date is today/tomorrow/yesterday;
  today's header renders in the accent color. Each header shows the group's
  task count.
- Clicking a day cell (adjacent-month cells included) selects that date and
  scrolls the time line to that group; selection itself never re-queries.
- Task rows inside groups are the §5 rows with all their interactions
  (toggle, detail, inline edit, context menu). Quick add, search (flat
  results, as in every view), and the Show Completed toggle behave as in
  the other views. Empty month (no overdue, no month tasks) → `taskListEmpty`.
- Status bar: `statusShowCalendar`.

Data-layer contract (all platforms, names may follow platform style):

- `get_tasks_in_range(start_date, end_date, include_completed)` — tasks
  with `due_date` between the bounds inclusive, `completed = 0` unless
  `include_completed`, ordered `due_date ASC, id DESC`. The overdue group
  reuses this with bounds `1900-01-01` … `day-before-today`.
- `get_due_day_counts(start_date, end_date)` — `(due_date, count)` rows for
  incomplete dated tasks in the range, `GROUP BY due_date`.

## 5. Task row

- 18px circular checkbox: incomplete = hollow ring; complete = ring +
  check in accent; completed text gets strikethrough + tertiary color.
- Meta line under the text when present: `🗓 dueDate [🕐 HH:mm]` and a
  single-line-ellipsized notes preview.
- `ⓘ` button (always visible) opens the detail dialog.
- Edit mode (double-click row): text field focused+selected; Enter=save,
  Esc=cancel, click-outside=save; date/time buttons open pickers and write
  through immediately; notes field saved on exit. Text changes re-run
  ExtractTimeCommand (a new trailing date command updates the due date).
- Context menu: Toggle Completed, Delete, and Move to List ▸ (other lists,
  `{icon} {name}`) when they exist.

## 6. Detail dialog

450px: task text (multiline), notes (multiline), date + time buttons with
pickers. Save (blank text silently ignored), Delete (confirm first), Cancel
(discards everything). After save/delete the task pane refreshes wholesale
(the task may have left the current view).

## 7. Pickers

- Date: calendar bounded 1900-01-01…2100-12-31; Clear → no date.
- Time: hour 00–23 + minute in 5-minute steps (00…55); current minute
  rounds to nearest 5; Clear → no time.

## 8. Menus / app-level

- File: New Database (save panel, default name `tasks`), Open Database
  (*.db), Close Database (confirm), Quit/Exit.
- Settings: Language (简体中文 / English, runtime switch, persisted in
  config `language`), Dark Mode toggle (**not persisted** — always starts
  light; native apps may follow the OS but the manual toggle stays).
- Tools: Install / Uninstall Command Line Tool.
- Help: About — `Taskly v<version>` + `© 2026 Taskly Team` + `aboutContent`.

## 9. Reminders (all platforms)

- Check every 60 s while a DB is connected; plus one check at startup.
- Due = incomplete ∧ has due_date ∧ `combine(due_date, due_time|00:00) ≤ now`
  (overdue included, however old).
- Each task notified at most once per session (dedupe set, reset when the
  DB changes). Startup: ≤3 overdue → one notification each; >3 → single
  summary `"<N> task(s) overdue"`. Everything seen at startup is marked
  notified.
- Notification: title `⏰ 任务到期` (reminderTitle), body
  `<text>\n<reminderDueAt>: <dueDate[ dueTime]>`.
- Never crash: missing notification permission or any transport failure is
  swallowed for the session (this crashed on macOS once — 0.6.1 regression —
  never again). No click-through action required.

## 10. Validation

Task text non-empty ≤1000 chars; list name non-empty ≤100; date year
1900–2100; (search keyword ≤200 — CLI layer). Error messages from i18n.

## 11. i18n

All user-facing strings come from `shared/i18n/{zh,en}.json` (copied into
each app; CI verifies byte-identity). `T(key)`: current language → zh
fallback → key itself. `{0}` placeholders formatted positionally. Default
zh; persisted in config.

## 12. Known v0.6.4 quirks — resolved in native apps

- GUI quick-add stores "now" as dueTime for `+1d` (CLI semantics differ):
  native apps adopt the **CLI semantics** (pure-date intent clears time) in
  the GUI too.
- Completed view has no stable order: native apps sort completed-last by id
  DESC within the view for determinism.
- GUI has no search field (CLI-only search): native macOS/Windows/Linux
  apps **add** a search field (product decision, flagged as an intentional
  delta from 0.6.4).
