# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- **List icon/color pickers upgraded to a shared catalog** (all platforms):
  emoji data now lives in `shared/emoji.json` (8 categories × 12,
  Windows 10 font-safe) synced like i18n, with localized category tabs;
  the color palette grows 10 → 12 presets (brown `#A2845E`, mint
  `#00C7BE`). macOS gains a tabbed emoji picker; Linux replaces its
  emoji/hex-value text dropdowns with a tabbed FlowBox grid and color
  swatches; Windows switches categories via a dropdown over the same
  catalog. DESIGN-TOKENS documents the picker contract.
- **Reminders-parity task interactions**: hover reveals the row fill plus
  one-click 今天/明天 schedule chips; ⌘/⇧ multi-select with batch context
  actions (complete/schedule/delete/move apply to the whole selection —
  deletes show a single undo banner); ↑/↓ keyboard navigation with
  ⇧-extend, Return expands the selected row, Esc collapses/clears; the
  info button expands the row **in place** (title, date/time chips,
  borderless notes — edits commit on collapse) instead of a modal sheet;
  completed tasks group under a collapsible "已完成 N" header; double-click
  a sidebar list to rename; right-click gains 详细信息 and 自定日期….

### Changed
- **Quick add redesigned**: accent + button, focus-highlighted border, and
  a live parse-preview chip — typing `明天买菜` / `standup @9am` shows the
  parsed schedule (今天 / 明天 / 10月8日 · 09:00) before Enter.
- **Task detail sheet redesigned as the spec'd immersive editor**
  (DESIGN-TOKENS): no dialog title — the task text is the title (18px
  semibold borderless); borderless notes with a tertiary placeholder;
  date/time as rounded chips (accent border when set, hollow "add" chips
  otherwise) opening a graphical calendar and a 5-minute-step HH:mm
  picker; bottom row of red-text Delete, plain Cancel, accent-filled
  Save. Fixed: clearing the date no longer leaves a stale dueTime on
  save. List edit sheet aligned to the same design language.

## [1.0.0] - 2026-09-30
### Added
- **Online updates on all three platforms** (contract: `shared/spec/UPDATE.md`)
  — silent check at launch (≥4 h throttle, config `last-update-check`) plus
  a `Settings ▸ 检查更新… / Check for Updates…` menu item everywhere.
  Windows: Velopack over GitHub Releases with delta packages (launch +
  manual check, dialog → install & restart). macOS: zero-dependency
  updater — signed `update-manifest.json` from the latest release
  (Ed25519 via CryptoKit), artifact sha256, atomic in-place bundle swap
  with rollback, then relaunch. Linux: same manifest feed over libsoup-3,
  sha256 verification, in-place prefix replace when writable, otherwise
  the releases page opens. Release pipeline now ships the macOS zip, a
  signed manifest and `manifest.sig` on every tag (signed only when the
  `UPDATE_ED25519_PRIVATE_KEY` secret is configured; keys via
  `scripts/update-keys.sh`, manifest via `scripts/make-update-manifest.sh`).
- **Golden CLI suite** (`shared/cli-golden/`): 61 shared cases pinning
  identical argv → identical stdout/stderr/exit code across platforms,
  each run against a fresh seeded database; macOS runner
  (`apps/macos/scripts/golden-cli.sh`) replaces the old grep-based smoke
  step in `native.yml`. Windows/Linux runners adopt the same fixture.

- **Task-row context menu** (spec §5): right-click a row for toggle
  completed, delete (no confirmation from the row, per contract), and
  move to list ▸ — the Windows GUI previously had no delete path.
- **Immersive task editor** (Windows): the task text is the title — an
  18px borderless input — with borderless notes, and a red Delete with
  confirmation.
- **Keyboard shortcuts, window-wide** (menu-labeled): Ctrl/Cmd+1…4 switch
  Today/Planned/All/Completed, Ctrl/Cmd+N focuses quick add,
  Ctrl/Cmd+F focuses search, Ctrl/Cmd+Shift+C toggles Show Completed,
  Ctrl/Cmd+Shift+N new database, Ctrl/Cmd+O open.
- **Restructured menu bar**: File / View / Tools / Settings / Help — the CLI
  installer lives under Tools, every smart view is reachable from the View
  menu.
- **Reminders-aligned layout**: the search field sits inside the sidebar
  above the smart-list tiles; the window header is a toolbar row plus an
  independent large-title block; Show Completed lives in the View menu.
- **Reminders-grade task rows**: checkbox rings take the task's list color;
  due dates render localized via the platform culture
  (today/tomorrow/yesterday/`Aug 31`/`8月31日`) with semantic color —
  overdue incomplete in red, due today in accent, completed always
  secondary; rows select and hover with quiet fills, and the row info
  button reveals on hover; list changes animate (add/remove transitions).
- **Large view header** (24 px title + 13 px subtitle: full date under
  Today, the displayed month under Calendar, open/completed counts
  elsewhere); search lives in the header toolbar (Reminders convention),
  quick add is the pane's single prominent input.
- ~50 new bilingual strings shared via `shared/i18n` and verified
  byte-identical in CI.
- Linux About window (libadwaita `AboutWindow`, PRODUCT-SPEC §8 parity) and
  a header-bar search entry (Gtk.SearchEntry).
- Windows crash telemetry floor: unhandled XAML-thread exceptions append to
  `~/.taskly/crash.log` (opt-in Sentry remains the commercial plan).

### Changed
- **macOS menu bar aligned to PRODUCT-SPEC §8**: About moved from the app
  menu to Help (replacing the dead "Taskly Help" placeholder), the
  duplicate system View menu and window-tabbing items are gone
  (`NSWindow.allowsAutomaticWindowTabbing = false`), File's system
  Close/Close All no longer collide with Close Database's Cmd+W, and the
  Tahoe window-tiling group is suppressed. Leftover empty system menu
  shells are pruned on launch and after each menu closes. The Edit menu
  keeps only standard editing commands plus the system text-input items.
- **macOS UI realigned to DESIGN-TOKENS**: smart views are now the contract's
  34px neutral chips (2×2 grid, radius 8, 8px gaps) with colored SF Symbol
  glyphs, 13px labels and quiet 12px counts — replacing the oversized
  saturated tiles; all emoji glyphs (tiles, due-date/time chips, empty
  states) replaced with SF Symbols; list rows and the selected state use
  surface cards with a quiet selection fill (no accent focus ring); the
  Completed token returns to spec gray `#8E8E93`; task rows get the 44px
  min height, a centered 20px list-color checkbox, and a meta line that
  leads with the owning list (dot + name) in multi-list views; the info
  button sits at 45% opacity until row hover; quick add is the contract's
  36px with radius 10; window default size is 1280×880.

- License finalized: desktop core AGPL-3.0 (was Apache-2.0), open-core model.
- Release engineering: canonical root `VERSION` file with a release
  preflight that fails the pipeline on cross-platform version drift;
  reproducible native tag builds; a UIA end-to-end suite
  (`scripts/e2e/e2e-windows.ps1`) drives 38 user-flow checks against a
  disposable database.
- Status bar wording reads naturally ("List: 工作", "All tasks").
- Tile hover/selection states use a saturation language: the active view's
  tile stays at full saturation with a white inset ring while the rest
  recede; the Completed tile is green (`#34C759`, done semantics);
  transitions ease over 120 ms (macOS/Linux).
- Default window 1280×880 — the calendar rail plus time line cannot fit a
  1024×768 physical window at 150% DPI; below ~420 logical px of pane
  width the month rail yields to the day-group time line.

### Fixed
- **macOS: crash on every GUI launch on macOS 26** — `AppState.init` read
  the bare `NSApp` global, which is still nil while SwiftUI (macOS 26)
  constructs the App struct before creating `NSApplication`; the force
  unwrap trapped before the first frame (EXC_BREAKPOINT). Both the
  appearance getter and the KVO registration now use
  `NSApplication.shared`, which creates the app object on first touch.
  Regression test `AppStateInitTests` reproduces the nil environment.
- macOS CLI: `add` echoed the built task without the joined `listName`,
  and `update --list` echoed the **previous** list's name after a move —
  both now read the stored row back (CLI-SPEC pins the echo).
- macOS CLI: `lists --json` always reported `pendingCount: 0` (the
  computed count was dropped on the JSON path; the human-readable path
  was correct).

The first release of the native rewrite (SwiftUI / WinUI 3 / GTK4-libadwaita,
zero shared runtime code, one behavioral contract in `shared/spec/`). The
Avalonia line (≤ 0.7.0) is retired; releases before this one belong to a
different architecture and are no longer published.

- **Windows: crash on entering the calendar view** — a synchronous
  PropertyChanged between the year and month assignments let the month grid
  render with month `0` and `DateTime` threw inside XAML layout (native
  fail-fast, no managed trace). Guarded in the pane and the view-model.
- Windows day cells / weekday header read theme colors from the static
  `UiTheme` projection instead of `Application.Resources` indexer lookups,
  which cannot see `ThemeDictionaries`.
- Windows smart tiles: two-row geometry (glyph and count on top, label at
  the bottom — fixes a glyph/label overlap) on chrome-free template buttons,
  so hover lifts instead of graying the fill and keyboard/UIA access is
  preserved; icon-only buttons and dialog inputs carry accessibility names.
- Windows calendar day groups now regenerate on a runtime language switch
  (their headers are pre-formatted strings).
- zh status line no longer renders the duplicated "9月月".
- macOS: deterministic release packaging arguments; `.app` version wired to
  the canonical VERSION file; universal builds copy from the multi-arch
  SwiftPM output directory.

## [0.7.0] - 2026-08-24

### Changed
- **Theme redesign — macOS Reminders style**: replaced the Anthropic-inspired warm
  palette (Pampas cream / Crail terracotta) with a neutral Reminders-style theme:
  pure-white content area, light-gray sidebar, system-blue accent (`#007AFF`),
  Reminders-semantic smart-list tiles (Today blue / Scheduled red / All & Completed
  gray), and a layered Reminders-style dark mode. New lists default to system blue.
- App icon regenerated as a blue rounded square; website (homepage + manual)
  reskinned to the same neutral palette, and the homepage mockup now mirrors the
  app exactly: bordered quick-add input, secondary-gray task dates, 280px sidebar,
  18px list titles, real macOS traffic-light colors.

### Fixed
- **Windows CLI install lost native libraries**: `install-cli` copied only the exe,
  so the installed `taskly` command was missing `e_sqlite3.dll` and every database
  command failed with exit code 4. The installer now copies the full app directory
  (DLLs, deps/runtimeconfig, runtimes/), and single-file publishes embed native
  libraries (`IncludeNativeLibrariesForSelfExtract`), so a bare exe works standalone.

## [0.5.2] - 2026-08-04

### Fixed
- **Windows IME text duplication (root cause)**: typing Chinese (and other IME
  languages) into any text box on Windows caused the last character(s) to be
  repeated (e.g. "完成" → "完成成"). This was an upstream regression in
  Avalonia 11.2.7 ([Avalonia#18661](https://github.com/AvaloniaUI/Avalonia/issues/18661)).
  Upgraded Avalonia from 11.2.7 → **11.2.8**, which ships the official
  "Fix Windows IME" patch. The earlier 0.4.6 workaround (removing TwoWay
  bindings) addressed a separate binding-layer issue but did not resolve the
  library-level duplication.

## [0.4.9] - 2026-08-03

### Fixed
- Sidebar disabled state: removed `IsEnabled` binding (caused ugly focus borders on
  disabled buttons). Interaction handlers now guard on `IsConnected` in code-behind.
- Website mobile responsive: comprehensive breakpoints for phones.
- Centered hero buttons on mobile.

## [0.4.8] - 2026-08-03

### Fixed
- Quick-add input box height jumps when typing: fixed `Height` + `Padding` and
  removed `:focus` border thickness change that caused 1px height jump.

## [0.4.7] - 2026-08-03

### Fixed
- Windows installer naming unified: `Taskly-win-Setup.exe` → `taskly-{version}-windows-x64.exe`.

## [0.4.6] - 2026-08-03

### Fixed
- **Windows IME text duplication**: removed TwoWay binding from QuickAddBox that
  caused CJK input characters to repeat on Windows.
- **No-database guard**: sidebar now properly blocks all interactions when no
  database is connected (was only guarding TaskPane, not ListPane).

## [0.4.5] - 2026-08-03

### Fixed
- New database dialog default filename was `tasks.db.db` (double extension).
  `SuggestedFileName` changed from `"tasks.db"` to `"tasks"`.

## [0.4.4] - 2026-08-03

### Added
- **Default list icon/color**: new lists get a default emoji (📋) and Crail
  terracotta color when the user doesn't pick one. Mimics macOS Reminders.

### Changed
- List rows now have a subtle surface background + divider border for clear
  visual container (was transparent — looked like floating text).

## [0.4.3] - 2026-08-03

### Fixed
- **DMG `.background` folder visible**: appdmg always creates an empty
  `.background` directory. Now physically removed after DMG generation.

## [0.4.2] - 2026-08-03

### Added
- **Unified app logo**: single SVG source → derived `.icns`, `.ico`, `.png`,
  and favicon across all platforms. Crail terracotta rounded square + white
  checkmark.
- Windows: `ApplicationIcon` in csproj + `--icon` flag in vpk pack.
- Website: inline SVG logo in nav, SVG favicon.

### Fixed
- Linux `taskly.png` was a solid color block (missing checkmark).
- Website favicon was a blue globe placeholder.

## [0.4.1] - 2026-08-03

### Fixed
- DMG `.background` folder: attempt to hide via `ds_store` icon repositioning
  (superseded by complete removal in 0.4.3).

## [0.4.0] - 2026-08-03

### Fixed
- App icon generation: moved after Pillow install step (CI was failing because
  `make_icon.py` couldn't import PIL).

## [0.3.9] - 2026-08-02

### Fixed
- List item selection/hover visibility: raised alpha from 12%→22% (selection)
  and 4%→8% (hover). Items were nearly invisible on the warm sidebar.

## [0.3.8] - 2026-08-02

### Added
- Ad-hoc code signing for macOS `.app` (`codesign --force --deep -s -`).
- DMG `.background` folder hidden via `chflags hidden`.
- Release notes include macOS first-launch instructions (`xattr -cr`).

## [0.3.7] - 2026-08-02

### Added
- **Professional DMG**: `node-appdmg` with `/Applications` symlink, background
  image, and icon layout. Drag-to-install experience.
- CI-generated background image (Pillow) with warm palette.

### Fixed
- `pip install pillow` → `python3 -m pip install` for reliable Pillow import on
  macOS runners.

## [0.3.6] - 2026-08-02

### Fixed
- DMG background generation: added `actions/setup-python@v5` for consistent
  Python environment (pip/python3 mismatch on macOS runners).

## [0.3.5] - 2026-08-02

### Fixed
- Linux `.desktop` Categories fixed to standard `Office;ProjectManagement`.
- Windows vpk diagnostics output.
- AppImage placeholder icon generated (Crail terracotta 256×256).

## [0.3.4] - 2026-08-02

### Fixed
- AppImage: `APPIMAGE_EXTRACT_AND_RUN=1` for CI FUSE compatibility.
- Velopack: `VelopackApp.Build().Run()` added to Program.cs.

## [0.3.3] - 2026-08-02

### Fixed
- Release workflow: create `build/` directory before packaging.

## [0.3.2] - 2026-08-02

### Changed
- Website redesign: Anthropic warm palette (Pampas cream + Crail terracotta),
  Newsreader serif headings, CLI feature section, dynamic GitHub Release links.
- Task mockup aligned to real `TaskItemRow.axaml` structure.

## [0.3.1] - 2026-08-02

### Fixed
- Linux AppImage: install libfuse2 + use `APPIMAGE_EXTRACT_AND_RUN` for CI.
- Windows Velopack: add `~/.dotnet/tools` to PATH so `vpk` is found.

## [0.3.0] - 2026-08-02

### Changed — proper platform-native packaging
- **macOS**: now ships as `.dmg` containing a proper `.app` bundle (was a raw
  zip). The app name shows as "Taskly" in the menu bar (was "Avalonia
  Application"). NativeMenu integrates with the system menu bar.
- **Windows**: now ships as a Setup.exe installer via Velopack (was a raw zip).
- **Linux**: now ships as `.AppImage` (zero-install) + `.deb` (Debian/Ubuntu).
- **Self-contained**: all builds now use `--self-contained true` — users no
  longer need to install the .NET runtime separately.
- Release workflow restructured into per-platform jobs.

### Notes
- macOS builds are unsigned (notarization requires an Apple Developer account).
  On first launch, right-click → Open to bypass Gatekeeper.
- `PublishTrimmed` is intentionally disabled to avoid reflection-related
  runtime failures. Builds are ~70-90MB.

## [0.2.2] - 2026-08-02

### Fixed
- **Close database did nothing**: ConfirmDialog used `ShowDialog<bool>` but closed
  with parameterless `Close()`, so the result was always false — every confirm
  dialog silently failed (close db, and any other confirm-dependent action).
  Fixed by reading the `Result` property after `ShowDialog`.
- About dialog version string updated to 0.2.1.

## [0.2.1] - 2026-08-02

### Fixed
- Release build: create `build/` directory before zipping on Linux/macOS
  (was failing with "Could not create output file").

## [0.2.0] - 2026-08-02

### Added
- **`install-cli` / `uninstall-cli`**: install the `taskly` command to the
  system PATH from the GUI (Tools menu) or CLI. macOS/Linux: shell wrapper in
  `~/.local/bin` (auto-adds to shell PATH); Windows: `taskly.cmd` + user PATH
  registry update. After install, `taskly` works from any terminal.
- **Command-line interface (CLI)** for AI agents and scripting. The same
  binary serves GUI (no args) and CLI (subcommands), without booting Avalonia
  in CLI mode. Subcommands: `list`, `lists`, `add`, `update`, `done`, `undone`,
  `rm`, `search`, `mklist`, `rmlist`. JSON output via `--json`, stable exit
  codes, idempotent done/undone. Powered by System.CommandLine 2.0.
- **AGENTS.md** with build/run/CLI/architecture guidance for agents and devs.
- macOS NativeMenu scaffolding (active when packaged as `.app`).

### Changed
- **Visual redesign** in Anthropic / Claude style: warm Pampas cream
  background, Crail terracotta accent, low-saturation smart-list tiles,
  softer corner radius and spacing. Replaces the cold Apple palette.
- **Task item interaction**: double-click to edit (text + date + time +
  notes in one place); metadata hidden by default to save space.
- **Sidebar** resizes via GridSplitter and collapses fully.
- **Title bar** reflects the currently selected list/view.
- Full **i18n** coverage across menus, dialogs, tooltips, watermarks.

### Fixed
- Toggling completion now correctly filters the task out of the default view.
- Closing the database clears the UI (was leaving stale content).
- List rows clickable across the full width (hit-testing fix).
- Time picker digits centered (rebuilt as hour/minute ComboBoxes).
- Input box no longer jumps height on focus.
- Numerous crashes from async edit-mode save (NRE on DataContext change).

## [0.1.0] - 2026-07-30

### Changed
- Rewrote the entire application with [Avalonia 11](https://avaloniaui.net/) and .NET 10 (C#),
  replacing the previous Flutter implementation while preserving every feature.
- State management moved from Provider/ChangeNotifier to CommunityToolkit.Mvvm (MVVM Toolkit).
- Dependency injection moved from GetIt to Microsoft.Extensions.DependencyInjection.
- SQLite access moved from sqflite to Microsoft.Data.Sqlite.

### Added
- Full binary compatibility with databases created by the previous Flutter release
  (identical `lists` / `tasks` schema, `user_version = 4`, migration history preserved).
- Continuous integration workflow (build + test on push and pull request).
- Cross-platform release builds for Windows, macOS (x64 / arm64) and Linux via GitHub Actions.

### Fixed
- Reactive property notifications for connection state and task collections, so the
  quick-add box and smart-list counts refresh reliably after database operations.
- Modal dialogs (emoji / color pickers) now use awaited `ShowDialog`, eliminating the
  race where a selection was not applied back to the list editor.

## [0.0.2] - 2026-02-02

### Added
- Refined platform icons on download page.
- Updated documentation mockups to match app UI.

### Fixed
- Fixed database path issue for custom locations.
- Fixed cursor positioning issues in text fields.
- Fixed task selection and deselection logic.
- Fixed layout alignment for dates and notes.
- Fixed note editing interaction bugs.
- Fixed language switcher on documentation site.

## [0.0.1] - 2026-01-29

### Added
- Initial release of Taskly.
- Core task management: create, edit, delete tasks.
- Task lists: organize tasks into customizable lists.
- Smart date parsing: naturally scheduled tasks.
- Local data persistence using SQLite.
- Responsive UI matching macOS Reminders style.
- Dark and Light mode support.
- Multi-language support (English, Chinese).
- Documentation landing page.
