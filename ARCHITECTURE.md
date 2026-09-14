# Taskly Architecture — Native Platform Rewrite

> Status: **Adopted** (supersedes the single-stack Avalonia architecture for all new work)
> Decision date: 2026-09-15

## 1. Context

Taskly v0.6.x ships as a single Avalonia 11 + .NET codebase. Feature-complete for
v1, but cross-platform UI toolkits impose a ceiling we keep hitting:

- Platform-feel gaps: file dialogs, IME (Windows IME character duplication —
  Avalonia#18661), keyboard navigation, accessibility, HiDPI, menu bar
  integration all need per-platform workarounds inside a toolkit that owns the
  whole window.
- Upstream regressions land in our release notes, not ours to fix.
- No credible path to native iOS/Android from Avalonia.
- A commercial desktop product must feel like a *platform citizen* on every OS.
  "Close enough" is not close enough.

## 2. Decision

**One product, native per platform, one repository.**

Each desktop app is written in the platform's first-party UI stack. No shared
runtime code, no embedded web views, no FFI core. Consistency comes from a
shared *contract* (specs, data format, CLI, strings, design tokens), enforced by
CI and conformance tests — not from shared implementation.

| Platform | Stack (first-party) | UI framework | Data access | Packaging | Future mobile |
|---|---|---|---|---|---|
| macOS | Swift 6 (+ SwiftUI, AppKit interop) | SwiftUI, min macOS 14 | libsqlite3 (system) | `.app` + notarized DMG | **iOS / iPadOS: reuse this codebase** (SwiftUI is cross-Apple; add adaptive layout targets) |
| Windows | C# / .NET 10 | WinUI 3 (Windows App SDK), Fluent 2 | `Microsoft.Data.Sqlite` | Self-contained exe + MSIX | — |
| Linux | Rust (edition 2021) | GTK 4 + libadwaita (GNOME HIG) | `rusqlite` (bundled SQLite) | Flatpak + tarball | — |
| Android (future) | Kotlin | Jetpack Compose (Material 3) | `androidx.sqlite` | AAB / Play | — |

Why no shared core library (Rust/C with FFI)?

1. The business core is thin: SQLite CRUD, date parsing, filtering. The cost of
   duplicating it is smaller than the cost of an FFI boundary in every build
   and every platform's debugger.
2. Native purity is the whole point of the rewrite; a foreign core drags its
   own runtime into each binary.
3. The shared artifact that actually prevents drift is the **contract**
   (§4), which is testable without shared code.

## 3. Repository layout

```
taskly/
├── apps/
│   ├── macos/          Swift package (app + CLI in one binary) + tests + bundle scripts
│   ├── windows/        WinUI 3 solution (app + CLI in one exe)
│   └── linux/          Rust crate (app + CLI in one binary) + Flatpak manifest
├── shared/
│   ├── spec/           PRODUCT-SPEC · DATA-FORMAT · CLI-SPEC · DESIGN-TOKENS  ← canonical
│   ├── i18n/           zh.json / en.json  ← single source of all user-facing strings
│   └── assets/         icon sources (SVG/PNG), brand
├── scripts/            sync-i18n.sh · verify-parity (CI helpers)
├── src/Taskly/         LEGACY Avalonia app — frozen reference implementation.
│                       Kept for behavioral reference during the parity push;
│                       deleted at native 1.0 (git history retains it).
├── packaging/          legacy packaging (frozen, as shipped for 0.6.x)
└── .github/workflows/  ci.yml (legacy, while it ships) · native.yml · release-native.yml
```

**Monorepo, not polyrepo**, because: one product, one version, one changelog;
a schema migration must land in three apps + the spec in a single atomic
commit; solo-developer overhead of three repos (issues, releases, CI drift)
outweighs nothing. Platform CI jobs are isolated by `paths:` filters so a
macOS-only change doesn't burn Windows runners.

## 4. The contract (what keeps three codebases one product)

`shared/spec/` is canonical. Every platform implementation must satisfy:

| Contract | Enforced by |
|---|---|
| `DATA-FORMAT.md` — SQLite schema (user_version 4), column↔field mapping, storage formats, WAL pragmas, `~/.taskly/config.ini`, default-DB resolution | Conformance tests open a fixture DB and round-trip every column on every platform (CI) |
| `CLI-SPEC.md` — subcommands, flags, JSON field names, exit codes 0/1/2/3/4, date syntax | Golden-CLI test suite: identical argv → identical JSON stdout, per platform (CI) |
| `shared/i18n/*.json` — every user-facing string, zh + en | `scripts/verify-i18n.sh`: platform copies byte-identical to canonical; no missing keys |
| `DESIGN-TOKENS.md` — color ramp (light/dark), spacing, type, iconography | Platform constant files reviewed against tokens; screenshot tests (follow-up) |
| `PRODUCT-SPEC.md` — behavior: views, filtering, sorting, editing loops, reminders | Human QA checklist per release + UI tests (follow-up) |

## 5. Non-negotiables carried over from 0.6.x

- **DB continuity**: existing `tasks.db` files open in-place, schema untouched
  (`user_version = 4`). Migrations in any native app only ever append
  `oldVersion < N` steps in lockstep across all platforms — and always ship in
  the same release on all platforms.
- **Cloud-sync story**: the DB is a single file the user may place in a synced
  folder (iCloud/OneDrive/Dropbox). WAL mode stays on; all writes go through
  the same repository validation layer; no platform may add a second store.
- **Agent CLI**: `taskly <subcommand> [--json|--db|--quiet]` keeps working from
  the same binary as the GUI (no GUI runtime initialized in CLI mode), same
  stdout/stderr split, same exit codes.
- **Bilingual zh/en at runtime**, light/dark themes following the OS with a
  manual override.

## 6. Versioning & releases

- One product version, one `CHANGELOG.md`. A release tag `vX.Y.Z` builds all
  platforms from the same commit (`.github/workflows/release-native.yml`).
- Artifacts: macOS `.dmg` (arm64 + x64, signed & notarized), Windows
  self-contained `.exe` installer + MSIX (signed), Linux Flatpak + portable
  tarball.
- Platform apps may add **native-only** features later (e.g. macOS Shortcuts,
  Windows widgets), gated behind the contract so shared behavior never forks.

## 7. Migration plan

1. **Phase 0 (this restructure)**: monorepo layout, contracts, all three
   native codebases, CI.
2. **Phase 1**: macOS reaches parity first (fastest to verify, flagship
   platform) → private beta.
3. **Phase 2**: Windows + Linux parity → private beta. Legacy removed from
   release pipeline.
4. **Phase 3**: native 1.0 GA across three desktops; delete `src/Taskly` and
   legacy CI/release workflows.
5. **Phase 4**: iOS/iPadOS from the macOS codebase; Android on
   Kotlin/Compose; optional cloud sync service (server-owned, not a file hack)
   evaluated only after mobile GA.
