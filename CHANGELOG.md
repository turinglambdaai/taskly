# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.2] - 2026-10-10

### Added
- **Windows MSI installs update online.** MSI installs used to be pointed
  at the releases page. The host now declares its install shape
  (`install-flavor=msi`) and the backend derives the sibling `.msi`
  asset from the feed's zip entry URL, checksums the download against
  the published `.msi.sha256` sidecar, and the install handoff runs a
  `msiexec /passive /norestart` upgrade (per-machine installs surface
  one UAC consent; msiexec log lands in `%TEMP%\taskly-update`).

### Fixed
- **The Windows hand-built rows kept light colors in dark mode.**
  Sidebar and task rows fetch their brushes from code at build time,
  so XAML theme bindings updated on a theme flip while those rows did
  not. A theme flip now repaints every hand-built row.
- **The Windows title bar stayed stock-light over a dark UI.** The
  native title bar now follows the app theme (Taskly sidebar palette,
  including buttons, hover, and inactive states).
- **The macOS menu bar mixed English and Chinese.** The system menus
  (File/Edit/View/Window/Help) carry AppKit's English template while
  the app's own menus drew from the i18n table. System menu titles are
  now re-applied from the i18n table on every menu resync (and pruned
  when PRODUCT-SPEC §8 does not define them), so zh renders
  `文件 视图 设置 窗口 帮助` and en renders `File View Settings Window
  Help`; Quit is localized too.

## [0.1.1] - 2026-10-10

### Fixed
- **The installed app has no icon.** `rivet.rktd` never declared
  `windows-icon`/`macos-icon`, so the packaged exe carried no icon
  resource and the macOS bundle fell back to the generic one. The
  launcher icons are now generated from `assets/icon_512.png`
  (`assets/taskly.ico`, 7 sizes; `assets/taskly.icns`, full iconset)
  and declared in the project file.
- **A black console window opened before the app on Windows.** Rivet's
  default diagnostic sink wrote every RVT1 protocol record to stderr,
  and the embedded Chez runtime lazily allocates a console on the
  first stderr write of a GUI-subsystem process. The backend now
  appends the same JSONL records (plus a local ISO-8601 `ts`) to
  `~/.taskly/diagnostics.log` instead — stderr is never touched, so
  no console ever appears.
- **The Windows sidebar kept twitching.** Every backend snapshot — the
  periodic poll and each `changed` event — rebuilt the list rows even
  when nothing had changed, so "My lists" visibly jumped on every
  pass. Snapshots are now fingerprinted (stable serialization of
  counts + lists + tasks) and an unchanged snapshot leaves the UI
  untouched.
- **The Windows quick-add text sat high in its box.** The 40px input's
  text rode the template's top-aligned content area instead of
  centering next to the 22px "+" button. The box now carries
  symmetric vertical padding (the WinUI 3 TextBox template routes
  both the placeholder and the typed text through the same padding)
  plus `VerticalContentAlignment="Center"` for templates that honor
  it.
- **An update download could rest at 100% forever.** The download
  loop waits for EOF with no timeout, so a connection that stalls
  without RST/FIN parked the backend worker at `downloading`/100
  indefinitely (and a dead backend left the host polling a frozen
  percent). The backend now watchdogs each download — 120 s without
  byte progress or 30 min wall clock breaks the worker into a clean
  phase=error — and the Windows host applies its own 30-minute total
  limit, so a download always ends in the consent dialog or a failure
  dialog.

## [1.4.0] - 2026-10-10

### Added
- **Native Linux packages.** Every release now ships `.deb` (installs
  under /opt/Taskly with a desktop entry), `.rpm`, and an `.AppImage`
  (self-contained GTK4 closure) alongside the tar.gz — for x64 **and
  ARM64** Linux, built by rivet 0.6.0's release pipeline. Package-
  manager installs upgrade through the package manager; the AppImage
  upgrades by replacing itself; the in-app updater keeps using the
  tar.gz channel.
- **Linux ARM64.** A second Linux leg (ubuntu-24.04-arm) produces the
  full Linux artifact set for ARM64 machines.

### Changed
- **The release pipeline moved to rivet 0.6.0** and its native
  `raco rivet release` flow: every platform leg now builds its
  installer, portable zip, and SBOM through one command (launch smoke
  included), and the Linux embeddable runtime comes from rivet's
  checksum-pinned composite action instead of a hand-rolled build.
- The macOS and Windows hosts migrated to rivet's `RivetTypes` codegen
  namespace (guarded upstream by a new codegen canary). Portable zips
  and SBOMs are per-architecture; SHA256SUMS covers every release
  asset.

## [1.3.0] - 2026-10-09

### Added
- **Intel Mac support.** Every macOS release now ships both
  architectures — `taskly-<version>-macos-arm64.zip` (Apple silicon)
  and `taskly-<version>-macos-x64.zip` (Intel, built on Intel
  runners). The signed update feed carries both, and each host picks
  its own architecture at compile time.
- **macOS drag-to-install images.** Both macOS architectures also ship
  a `taskly-<version>-macos-<arch>.dmg` alongside the portable zip.
- **Windows MSI installer.** `taskly-<version>-windows-x64.msi` joins
  the portable zip, built by rivet's native installer pipeline
  (WiX v5). Portable zip installs keep the fully automatic in-place
  update; MSI installs live under Program Files, so their updater
  explains the manual path instead of attempting a swap it cannot
  make — the guidance dialog opens the releases page.

### Documented
- **Windows ARM64** runs the x64 build through Windows on ARM's
  built-in x64 emulation (Racket ships no Windows-on-ARM runtime, so
  no native arm64 Windows package exists to build against).
- Linux native installers (deb/rpm/AppImage) land with rivet's
  installer pipeline (rivet#167) and will ride a following release.

## [1.2.1] - 2026-10-09

### Fixed
- **The macOS in-app updater could not finish its own download.** The
  artifact loop ran on the main actor: every byte hopped through the
  main executor, the transfer starved and URLSession aborted with
  request timeouts — and when all bytes did arrive, the loop suspended
  forever waiting for a stream end that HTTP/2 never signaled. The
  identical loop completes in seconds off the main actor. The download
  → verify → swap sequence now runs off the main actor, consumes the
  stream through a 64 KiB buffer (the old code hashed and appended per
  byte — 31 million CryptoKit calls), and stops at the size the signed
  manifest pins instead of waiting for EOF. Verified end-to-end against
  the live feed: check → offer → download → swap → relaunch.

## [1.2.0] - 2026-10-09

### Fixed
- **The macOS packages could not launch at all — 1.0.0, 1.1.0 and 1.1.1
  all shipped dead.** The host's SwiftPM resource bundle (i18n + emoji
  JSON) was never placed where the generated accessor looks for it, so
  every packaged app died instantly with `could not load resource
  bundle` (rivet#148); the release job skipped the launch smoke, so CI
  never noticed. Taskly no longer uses a SwiftPM resource bundle: the
  hosts read the staged product resources (`app/shared/i18n`,
  declared via the `resources` field in `rivet.rktd`, the same
  rivet#149 convention the Linux and Windows hosts follow), with the
  macOS resource lookup in one place (`HostResources.swift`). The
  release job runs the launch smoke again and the CI `macos-host` job
  boots the staged host for 8 seconds — this crash class cannot ship
  silently anymore.
- **The Windows and Linux packages never carried their i18n files.**
  The release pipeline staged `shared/i18n` into the stage, but every
  rivet build recreates the stage from scratch, so the copies were
  wiped before packaging and the hosts silently ran on their embedded
  fallback tables. Product resources now ride the `rivet.rktd`
  `resources` declaration and land inside the package on all three
  platforms.
- The macOS update feed migrated to the family's self-contained signed
  wrapper (`update-manifest.json` with the payload base64-embedded —
  no separate `manifest.sig` asset). This also drops the updater's
  dependency on the GitHub releases API.

### Added
- **Windows host: i18n and an in-app updater.** Every user-visible
  string in the WinUI3 shell now comes from the shared table (runtime
  language from the backend settings, embedded fallback otherwise), and
  the host can check, download and install updates: silent throttled
  launch check, `Settings ▸ Check for Updates…`, progress polling, and
  a quit-and-install handoff that swaps the install directory in place
  and restores it if anything fails (the failure is reported on the
  next launch).
- **Linux host: an in-app updater.** `Settings ▸ 检查更新…` checks the
  signed feed, downloads the tar.gz with a progress dialog and hands
  the user the verified file (open folder); install stays a manual
  extract, which is the family rule for tarball distributions.
- Backend: `check_updates` / `start_download` / `update_state` RPCs on
  `rivet/distribution` — the backend verifies the Ed25519-signed
  manifest and downloads the artifact (with a sticky per-install
  rollout bucket); hosts own only UI and install. Test suite grew from
  69 to 77 checks (`racket/tests/updater-test.rkt` covers the offline
  trust chain, progress accounting and the rollout bucket).
- Release pipeline: the publish job signs the manifest with the pinned
  rivet checkout; Rivet pin moved to `2fcdd091` (rivet#148 bundle
  staging + rivet#153 redirect-following update fetches).

## [1.1.1] - 2026-10-09

### Added
- **The macOS updater is wired in.** 1.1.0 shipped the signed update feed
  and the `UpdateService` engine, but nothing invoked it. `Settings ▸
  Check for Updates…` now checks the Ed25519-signed manifest on demand,
  and one silent check runs shortly after launch (throttled to once per
  4 hours via the `last-update-check` config key, bypassed by the menu).
  An available update is offered by version, downloads with visible
  progress, re-verifies the artifact sha256 and the unpacked bundle
  version, swaps the app in place and relaunches; a failed swap restores
  the previous bundle and the running version keeps working. Development
  copies (not under /Applications) get an honest "auto-update
  unavailable" answer instead of a network error.

### Fixed
- **`set_setting` never persisted anything.** The RPC built the new
  config with the immutable-only `hash-set` on the mutable hash that
  `read-config` returns, so every write threw and the hosts silently
  swallowed the RPC error — theme, language and last-selected list never
  survived a relaunch. It now uses `hash-set!`; a new backend contract
  test (`racket/tests/backend-test.rkt`) covers the write path, growing
  the suite from 62 to 69 checks.

### Changed
- Backend: a new `get_setting` RPC exposes raw config values to hosts
  (the macOS update throttle reads `last-update-check` through it, and
  the future Windows/Linux updaters will share it); `set_setting`
  accepts the integer-as-string `last-update-check` key and the config
  writer persists it (DATA-FORMAT §7).
- The [UPDATE](shared/spec/UPDATE.md) status table reflects reality:
  the macOS updater is fully wired; Windows and Linux host updaters
  remain documented follow-ups — until they land, update those hosts by
  manual download from the releases page.

## [1.1.0] - 2026-10-08

### Added
- **Linux is now a release platform.** The release pipeline builds and
  packages the GTK4 host on Ubuntu (`taskly-<version>-linux-x64.tar.gz`,
  sha256-summed), completing the three-desktop matrix alongside the
  macOS arm64 and Windows x64 zips. Launch smoke runs under xvfb before
  anything is uploaded.
- **Every release now ships a signed update feed.** The release pipeline
  generates `update-manifest.json` (all three platform artifacts) and
  signs it with the release Ed25519 key (`manifest.sig`); the macOS host
  verifies it before installing an update
  (`scripts/make-update-manifest.sh` regenerated for the Rivet asset
  names). The [UPDATE](shared/spec/UPDATE.md) contract documents the
  per-host updater status honestly.
- **The 61-case golden CLI suite now runs in CI**, byte-pinning
  stdout/stderr/exit codes of `scripts/taskly-cli.sh` on every push.

### Fixed
- `list --json` with an unopenable database now emits the leading `[]`
  on stdout before the exit-4 error JSON on stderr, restoring the v1
  byte contract (golden case `db-unopenable`).

### Changed
- Repository docs describe the Rivet line, not the archived v1 native
  line: README (en/zh), AGENTS.md, and the site release section were
  rewritten — the "archived" banner, dead `apps/` links, and the
  Vala/WinUI-3-rewrite platform table are gone; the release workflow and
  CI now pin the same Rivet commit.

## [1.0.0] - 2026-10-08

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
