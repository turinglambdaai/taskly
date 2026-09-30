# Taskly

A focused task manager. One product, one SQLite file, one agent CLI — one
shared application core, native UI on every desktop.

**English** · [中文](README.zh-CN.md)

[![License](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)

> **This branch is a rebuild.** Taskly is being rebuilt on
> [Rivet](https://github.com/turinglambdaai/rivet) — our Racket application
> framework: one Racket domain core driving first-party native UI shells over
> a typed RPC contract. The v1 native line (SwiftUI / WinUI 3 / GTK4-Vala,
> itself a rewrite of the 0.6.x Avalonia app) is archived on `main` and
> remains recoverable from git history. Rationale and milestones:
> [docs/RIVET-MIGRATION.md](docs/RIVET-MIGRATION.md).

## Status

| Piece | Stack | State |
|---|---|---|
| Domain core | Racket (`racket/taskly/`), SQLite schema v4 | ✅ complete, 56 contract tests green on all three OSes |
| Windows host | C++/WinRT + embedded Racket CS | M3 first runnable (Taskly UI over the backend) |
| macOS host | SwiftUI + typed client | porting in progress ([handoff](docs/MACOS-HANDOFF.md)) |
| Linux host | GTK4 + embedded Racket CS | first runnable (smart views, lists, add/complete/delete) |
| Agent CLI | Racket (M6) | spec'd in [CLI-SPEC](shared/spec/CLI-SPEC.md), not yet implemented on this branch — daily CLI still ships in the archived v1 apps |

## What the product keeps

- **Reminders-style UI** — smart views (Today / Planned / All / Completed),
  custom lists with emoji icons and colors, quick add with natural-language
  dates (`@10am`, `+1d`, `tomorrow`), due-task notifications, bilingual zh/en,
  light/dark. Spec: [PRODUCT-SPEC](shared/spec/PRODUCT-SPEC.md).
- **One data file** — your tasks live in a single SQLite file
  (`~/.taskly/tasks.db`, WAL) you can drop into iCloud/OneDrive/Dropbox for
  sync. The format is documented and stable:
  [DATA-FORMAT](shared/spec/DATA-FORMAT.md).
- **Agent CLI** — `taskly list|add|update|done|rm|search|…` with `--json`,
  stable exit codes, headless operation. Spec:
  [CLI-SPEC](shared/spec/CLI-SPEC.md).

## For developers

```
taskly/
├── rivet.rktd            Rivet app manifest (backend entry, protocol v1)
├── app/backend.rkt       Rivet backend entry
├── racket/               the domain core + its contract tests
├── windows/              C++/WinRT host
├── macos-host/           SwiftUI host
├── linux/                GTK4 host
├── shared/spec/          the contract: product · data · CLI · design tokens
├── shared/i18n/          zh/en single source
└── docs/                 migration decisions, handoffs, upstream backlog
```

### Build

```bash
# 0) Racket CS 9.x, with rivet linked (the checked-out rivet branch defines
#    what `raco rivet` does; Taskly needs M1 named records — merged to rivet main)
cd ../rivet && raco pkg install --auto --no-docs --name rivet --link file://$PWD

raco rivet doctor --json     # toolchain self-check
raco rivet build             # backend bundle + native host for this platform
raco rivet dev               # dev loop: rebuild + run
raco test racket/            # domain core tests
```

Platform hosts need their first-party toolchain (Windows App SDK / Xcode /
GTK4 + CMake + an embeddable Racket CS). See
[AGENTS.md](AGENTS.md) for the full map.

## License

AGPL-3.0 for the desktop core — the desktop app is open source and free to
use, fork, and study. Future commercial surfaces (mobile clients and cloud
sync) ship as separate projects under their own terms; see
[COMMERCIAL-CHECKLIST](COMMERCIAL-CHECKLIST.md).
