# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Task editing now has a discoverable, cross-platform commit contract: every
  native inline editor exposes Save and Cancel, date actions lead with Today,
  Tomorrow and This Weekend above the platform calendar, and saving reports
  progress before confirmed persistence. Explicit save failures keep the full
  draft available for correction instead of silently closing it.

## [0.2.6] - 2026-10-26

### Fixed
- **Windows task editing is compact and native instead of a tall utility
  form.** The selected row now presents a borderless title and quieter notes
  above one accessible date/time/list action line, with native theme and
  focus behavior plus consistent Enter/Escape handling across every field
  (#71).
- **Windows updates no longer send a verified ZIP to `msiexec` (error
  1620).** The host now persists the detected install flavor before every
  update check and dispatches the final handoff from the verified file's
  `.msi`/`.zip` extension, so artifact selection and installation cannot
  disagree.
- Smart-view counts now display `0` instead of leaving an empty trailing
  space. Windows and macOS match Linux for Today, Planned, All and Completed.
- **The product site's tab icon and manual nav logo follow the family
  palette again.** The terracotta rebrand recolored the page and the index
  nav logo but left `docs/favicon.ico` and `docs/taskly.svg` on the retired
  Apple-blue gradient, so browser tabs showed a blue icon over a terracotta
  page; `manual.html`'s nav logo stayed `#007AFF` too. All three now use
  the site accent (`#c15f3c` / hover `#a84e2f`) — the same mark as the
  index nav logo.

## [0.2.5] - 2026-10-26

### Added
- Shared-core reminder decisions on macOS, Windows and Linux: the Racket
  service now owns due-task eligibility, startup summaries, per-database
  de-duplication and delivery acknowledgement, while each native host owns
  permission and OS handoff. Windows gains the missing native reminder path,
  and stale database-switch decisions cannot leak into the new database (#62).
- An Automatically Check for Updates toggle in the Settings menu on every
  platform (config `auto-check-updates`, default on): silent launch and
  4-hour checks honor it, the manual Check for Updates… item always runs
  (#58).
- Network transparency: the macOS bundle ships an
  `InternetAccessPolicy.plist` declaring the update feed as the app's
  only network use — firewall apps (Little Snitch and friends) show the
  policy's per-host purpose and deny consequences to the user, and
  denying it leaves Taskly fully functional offline (#58).
- About dialog becomes the update/link/feedback portal on every platform:
  User Manual and Changelog links join Website and Report an Issue, and a
  diagnostics block (release identity, platform, database and config
  paths) carries a Copy Diagnostics button so a bug report can include
  the full context verbatim (#58).
- Release-kind acceptance: the update chain — signed-feed rejection,
  download cancellation, the N→N+1 lifecycle, data preservation, and the
  Linux AppImage in-place swap — is now an executable `release`
  requirement in `rivet-acceptance.rktd`, and the release pipeline's
  publish job runs the suite on the exact tree being published, so a
  release cannot ship without its update evidence (#58).

### Changed
- Reconcile the task interaction contract and public manual around the native
  inline editor: Enter/click-away saves, Escape cancels the complete draft,
  and packaged UI traces now exercise keyboard focus on all three hosts.
- Document the first-use-to-upgrade lifecycle, closed-app data backup, and
  rollback/manual recovery for every supported install shape (#58).

### Fixed
- macOS deletion now uses the same six-second delayed backend commit as
  Windows and Linux, so Undo restores the original task IDs and metadata and
  a database switch cannot leak stale delete IDs into the new database (#58).

## [0.2.4] - 2026-10-22

### Added
- Windows: native Ctrl/Shift task multi-selection, batch completion/move/date
  scheduling, and an inline editor for task details (#41, #42, #45, #50).
- Linux: native multi-selection and keyboard activation, batch completion/move/
  scheduling, and identity-preserving six-second undo for single and batch
  deletion (#33, #43, #46, #48).
- Windows: six-second reversible deletion for individual and selected tasks
  (#47).
- Windows: the shared app accelerators now work window-wide — Ctrl+1…4
  switch smart views, Ctrl+N focuses quick add, Ctrl+F focuses search,
  Ctrl+Shift+C toggles completed tasks, and Ctrl+Shift+N / Ctrl+O create
  or open a database.
- Linux: the About dialog now carries the same website and Report-an-Issue
  links as macOS and Windows (GtkAboutDialog cannot hold a second link,
  so the dialog is built on the plain family layout); Windows and Linux
  also gain the About © line, and the README and product site name the
  issue tracker as the feedback channel (#55).

### Changed
- Add an executable cross-platform product acceptance contract. Windows,
  macOS arm64/x64, and Linux now run shared Racket contracts, a real RVT1
  embedded-backend round trip, native compilation, verified packaging, and an
  accessibility-driven critical UI flow against a disposable user profile.
  The gate archives fresh interaction, accessibility, and platform diagnostic
  evidence; fixed-sleep boot smoke and CLI substitutions no longer count as
  proof of native product behavior (#15).
- Improve macOS DMG drag-to-install guidance, use the formal Taskly display
  name, and polish Windows installer and startup visuals (#27–#30, #26).
- Permit cancellation of Windows and Linux update downloads, and guard
  dependency pins across workflows (#24, #16).

### Fixed
- Linux: preserve full 64-bit SQLite IDs in GTK task/list selection, editing,
  completion and navigation; exercise large IDs in the native acceptance
  suite (#49).
- Linux: keep the staged-delete undo card attached to its persistent GTK
  container, avoiding a use-after-free during Undo/timeout; use the native
  GtkSearchEntry placeholder API and harden AT-SPI scans during row rebuilds
  (#54).
- Preserve quick-add drafts until asynchronous saves succeed on Windows,
  macOS and Linux (#32, #37, #38).
- Windows: honor the selected task list on creation, allow correction of
  misfiled tasks, and make cross-list search results editable with their
  true list identity (#35, #36, #39).
- Ignore stale asynchronous responses that could revert the Windows selected
  list or show Linux tasks under the wrong list (#40, #44).
- Preserve local wall-clock semantics for relative dates across daylight
  saving time transitions (#20).
- Correct Linux theme divider colors and Windows quick-add focus styling
  (#34, #31).

### Security
- Verify Windows MSI and Linux AppImage update payloads against artifacts
  authenticated by the signed update manifest (#21).

## [0.2.3] - 2026-10-17

### Changed
- "Check for Updates…" moved next to About per the family menu
  convention: App menu below About on macOS, Help menu (above About) on
  Windows and Linux — it had lived at the bottom of the Settings menu on
  every platform.

### Fixed
- **macOS: clicking the task checkbox did not complete the task.** The
  checkbox button's label is a stack of circles whose fill is transparent
  while the task is open, and SwiftUI hit-tests a plain button against its
  label's rendered content — so the effective click target was just the
  1.5pt ring stroke. Tapping the center, the natural place to click, did
  nothing: no state change, no error, and the engine never saw a
  `set_completed` call. The same missing-hit-shape pattern affected the
  row's info and collapse buttons, the sidebar's new-list plus, the pane's
  sidebar toggle, and the search clear button. Every one of these labels
  now carries an explicit `contentShape(Rectangle())` so the whole control
  area is clickable. Verified end to end with real mouse clicks against an
  isolated database: check, uncheck, and the state-bar count all update.

## [0.2.2] - 2026-10-16

### Fixed
- **Windows: the MSI update download followed no redirects and could
  never deliver a real installer.** The msi/appimage download path
  opened the release URL without redirections — GitHub answers those
  URLs with a 302 into the CDN, so the "download" was the empty 302
  body (no progress ever shown), and the checksum sidecar comparison
  was the only thing standing between the user and a 0-byte installer.
  The port now follows redirects like the signed-manifest zip flow and
  the sidecar fetch already do (the same 302 trap rivet#153 fixed
  upstream). Where an accelerated/mirror route returns the file
  directly, downloads keep working as before.
- **Windows: the title bar no longer shows the broken blank icon.**
  The system title-bar icon rendered as an empty placeholder glyph (the
  exe icon resource is not picked up for this install shape). The icon
  and its click-menu are now hidden for a clean title bar matching the
  macOS look; taskbar and Alt-Tab keep the real app icon.
- **The app forgot the manually opened database location.** Nothing ever
  wrote the `last-db-path` config key, so a database opened from the file
  menu was reopened only as long as the process lived — and a config
  rewrite (the update-check timestamp) silently dropped the pre-0.x
  underscore form (`last_db_path`) that earlier files carried. An OTA
  restart then fell back to the default empty DB and asked for the file
  again. Now `open_database` persists the path on success (all hosts),
  and config rewrites carry the legacy key through. Data was never at
  risk — only the remembered pointer was lost.

## [0.2.1] - 2026-10-16

### Changed
- **macOS: the hover quick-schedule chips (今天/明天) are gone from the
  task row.** Hover now only quiets the row fill and emphasizes the
  info button — hovering never moves row content, matching Reminders,
  which keeps its quick-date buttons in the details popover and the
  context menu. The one-click dates moved to where that intent lives:
  the expanded row's date popover now leads with 今天 / 明天 / 本周末
  (the coming weekend day) above the calendar.
- **macOS: the list now refreshes just past each local midnight**, so
  Today membership, 今天/明天 labels, and overdue colors are no longer
  stale in a window left open overnight.
- Windows/Linux: relative day labels, overdue red, and the due-today
  accent now parse the date part of timestamps stored by quick-add
  (`yyyy-MM-dd HH:mm:ss`) — such tasks previously rendered the raw
  timestamp and never matched 今天/明天/逾期.
- Windows: due-date labels gained the 昨天 relative word, and the
  completed-state date color now goes quiet like macOS/Linux; the
  tomorrow-specific tint was dropped (no other host has one).
- Linux: date comparison is normalized to -1/0/1 — string-compare sign
  differences ("09-30" vs "10-01" → +8) made yesterday detection and
  overdue red miss at month boundaries.

### Fixed
- **Windows: deleting a list now asks for confirmation** — the delete
  cascades to every task in the list with no undo; macOS and Linux
  already confirmed, Windows silently deleted on a single mis-click.
- **Update feed: the linux/arm64 tarball entry was missing**, so arm64
  Linux users never received update notifications even though arm64
  artifacts shipped. `make-update-manifest.sh` now lists and asserts
  all five feed artifacts.
- Release workflow: publishing no longer fails midway when the signing
  secret is absent (the manifest is simply omitted from the upload
  list), and re-runs converge — an existing release gets its notes
  edited and assets re-uploaded with `--clobber` instead of colliding.
- Release preflight now rejects lightweight tags (v0.1.0/v0.1.4/v0.2.0
  were lightweight) and checks `racket/info.rkt`'s version against
  VERSION (it had drifted at 0.1.0; now 0.2.0).
- Docs/site: the website no longer claims a single binary shipping GUI
  and CLI together (contradicting README's Honest gaps — the release
  packages don't include a standalone CLI yet); README states the
  per-platform status of the Reminders-parity interactions; golden
  suite counts corrected to 63; hardcoded contract-test counts removed.

## [0.2.0] - 2026-10-14

### Added
- **The About box now carries the full support surface on every host.**
  All three platforms show the license line (`aboutLicense`), a Website
  link (taskly.jrtx.site) and a Report-an-Issue link (the GitHub issue
  tracker); Windows and Linux also gained the version line macOS already
  had. Linux uses the GTK about dialog's native rows, Windows renders a
  stacked dialog with hyperlink buttons (PRODUCT-SPEC §8). A bug report
  now starts one click away from the failure it describes.
- **`taskly version` and `taskly check-update` (CLI).** `version` prints
  `Taskly <version>` (`--json`: version/channel/platform/architecture)
  from a new leaf `version.rkt`, so identity reporting never loads the
  update machinery. `check-update` runs the same signed-manifest chain as
  the GUI (fetch → Ed25519 verify → semver/channel selection) and prints
  up-to-date / available-plus-URL (`--json` mirrored); failures exit 1
  with the standard stderr JSON. Agents can finally ask a headless
  Taskly whether an update exists. Release identity stays single-source:
  `check-release-version.sh` now checks `version.rkt`.
- **GitHub issue templates** (bug report + feature request) so feedback
  from the About link lands structured.

### Changed
- **Update failure text now leaves the screen with the user** (contract
  added to `UPDATE.md`). The macOS sheet's error is selectable, the Linux
  error dialog's label is selectable, and the Windows update dialogs
  carry a "copy error" button that puts the failure message on the
  clipboard.
- Golden suite: `{{version}}` / `{{platform}}` / `{{architecture}}`
  normalization keeps the `version` case stable across releases and
  portable across CI platforms.

## [0.1.4] - 2026-10-14

### Changed
- **Rivet pin bumped to v0.11.0.** CI and Release install the catalog
  package from `#v0.11.0` (the root SwiftPM package, `rivet-host.vcxproj`
  and the `rivet::platform` CMake target are all consumed as a package on
  every host), and `setup-embed-racket` is pinned to `@v0.11.0` instead of
  floating `@main`. The workflow-level pin now lives in a single top-level
  `env: RIVET_PIN` per workflow — a bump is one edit instead of a
  grep-replace across jobs.

### Fixed
- **The updater's watchdog break path no longer orphans a `.partial`
  file.** The worker's outer handler caught `exn:break` (a stalled
  download broken by the watchdog) and set phase=error, but — unlike the
  `exn:fail` arms inside the download handlers — it never deleted the
  half-written `.partial`. A stalled download left the orphan behind
  until the next attempt's pre-clean. The break arm now removes the
  `.partial` the same way, and a rackunit test drives the real worker
  against a stalling loopback server, breaks it the way the watchdog
  does, and asserts the file is gone.

### Site
- **The product site (taskly.jrtx.site) moved to the family palette and
  gained a dark theme.** The Apple-blue/gray scheme (#007AFF/#F5F5F7) is
  replaced by the family spec values (#faf7f2/#ffffff/#1f1d1a/#6b6660/
  #e8e2d9/#c15f3c/#f7e5dd, radius 14), the nav logo follows the accent,
  and a manual dark theme (keepsake dark values) sits behind a nav toggle
  with an anti-flash head script and localStorage memory — explicit
  choice wins over the OS preference.
- **The index page defaults to Chinese and switched to data-i18n +
  dictionary mode** (title and meta description switch with the
  language). manual.html keeps its per-element attributes and continues
  to work; the site stays zero-dependency.

## [0.1.3] - 2026-10-13

### Fixed
- **The macOS in-app update no longer hangs forever at 100%** (issue #13).
  The download leg consumed `URLSession.AsyncBytes` byte-by-byte; when the
  stream's end-of-stream signal never surfaced, the loop parked its
  continuation permanently — all bytes delivered, the sheet stuck at
  100%, undismissable, reproducible on both 0.1.0 and 0.1.1 against the
  live feed. The download now runs as a delegate-driven
  `URLSessionDownloadTask` (`didFinishDownloadingTo` /
  `didCompleteWithError` are definitive), sha256 is computed from the
  file on disk in 1 MiB chunks (the ~30 MB artifact never sits whole in
  memory), and the request/resource timeout intervals bound a silent
  stall: a stalled download now surfaces a retryable error after ~60 s
  instead of hanging. The update sheet gained a Cancel button during the
  download; cancelling invalidates the session, the install task always
  resumes, and the phase machine settles back to idle.
- **The macOS swap handoff no longer depends on `NSApplication.terminate`
  going through.** A presented SwiftUI sheet vetoes the terminate
  sequence silently; the app then kept running, the swap script's
  payload directory was deleted by the still-running function's cleanup
  (`defer`) while the script slept, and the relaunch died on the
  single-instance lease held by the old process. The quit sequence now
  ends every sheet first, falls back to stopping the run loop after
  1.5 s, the swap script waits out the lease before relaunching, and
  stale swap work dirs are swept by a later launch (the script cannot
  reliably delete the directory bash is still reading from).
- **SIGTERM now shuts the Linux app down instead of killing the backend
  under a living window.** OS signals bypass the GTK main loop, so the
  orderly teardown never ran — `systemd --user stop`, session logout and
  `killall` all left a zombie window over a dead backend (the same
  exposure syncpilot#3 documented for this scaffold generation). The
  rivet shutdown hook installs once the embedded runtime finishes
  booting: installing in `main()` loses the race to the Racket runtime's
  own SIGTERM handler, which kept the hook inert. Teardown is
  exactly-once across the GTK and signal paths, with step traces in the
  host log.

## [0.1.2] - 2026-10-10

### Added
- **Windows MSI installs update online.** MSI installs used to be pointed
  at the releases page. The host now declares its install shape
  (`install-flavor=msi`) and the backend derives the sibling `.msi`
  asset from the feed's zip entry URL, checksums the download against
  the published `.msi.sha256` sidecar, and the install handoff runs a
  `msiexec /passive /norestart` upgrade (per-machine installs surface
  one UAC consent; msiexec log lands in `%TEMP%\taskly-update`).
- **Linux AppImage installs update in place.** When running as an
  AppImage, the backend derives the sibling `.AppImage` asset from the
  feed's tar.gz entry (arch names mapped: x64→x86_64, arm64→aarch64),
  verifies it against the release's `.AppImage.sha256` sidecar, stages
  it next to the running image and atomically renames it over
  `$APPIMAGE` with exec bits set — the host then asks for consent and
  re-execs the replaced image, Tauri-2 style. deb/rpm installs get
  pointed at the system package manager instead; tarball installs keep
  the download + manual-extract flow.

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

## [1.0.0] - 2026-09-30 (pre-reset native line)
> Version-line note: this and every 1.x entry in this file — including the
> second [1.0.0] above (2026-10-08) — belong to the pre-reset native line,
> kept here for history. When the Rivet rebuild became the mainline on
> 2026-10-10, releases were cleared and versioning restarted at 0.x, so the
> two [1.0.0] headings are not a typo.

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
