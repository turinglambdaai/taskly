# Taskly

A focused, keyboard-friendly task manager for macOS, Windows and Linux —
one Racket core driving a first-party native host on every desktop, an
agent-facing CLI, and a single local SQLite file.

[![release](https://img.shields.io/github/v/release/turinglambdaai/taskly)](https://github.com/turinglambdaai/taskly/releases/latest) ![platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey) ![built with](https://img.shields.io/badge/built%20with-Rivet-9333ea) [![CI](https://github.com/turinglambdaai/taskly/actions/workflows/ci.yml/badge.svg)](https://github.com/turinglambdaai/taskly/actions/workflows/ci.yml) [![License](https://img.shields.io/badge/license-AGPL--3.0-blue)](LICENSE)

**English** · [中文](README.zh-CN.md)

Taskly is built on [Rivet](https://github.com/turinglambdaai/rivet): the
entire domain — SQLite storage, scheduling, natural-language dates,
validation, and the CLI — lives in one Racket CS core, and every desktop
gets a thin first-party host over typed RPC. The hosts only render and
interact; all logic lives in the backend.

| Desktop | Host | 
|---|---|
| macOS 14+ (Apple Silicon) | SwiftUI |
| Windows 10+ (x64) | WinUI 3 |
| Linux (x64) | GTK 4 |

## Features

- **Reminders-style UI** — smart views (今天 / 计划 / 全部 / 已完成),
  custom lists with emoji icons and 12-color palette, light/dark that
  follows the system, bilingual zh/en with live switch.
- **Quick add with natural-language dates** — type 明天买菜 or
  `standup @9am +1d` and see the parsed schedule in a live preview chip
  before you hit Enter.
- **Reminders-parity interactions** — hover a row for one-click
  今天/明天 schedule chips; ⌘/⇧ multi-select with batch actions and a
  single undo banner; ↑/↓ navigation, Return expands the row in place
  (title, date/time chips, notes), Esc collapses; completed tasks fold
  under a collapsible header.
- **Due-task notifications** — a 60 s poll plus a startup check, deduped,
  capped at three separate banners (more → one summary).
- **One data file** — your tasks live in a single SQLite file
  (`~/.taskly/tasks.db`, WAL) you can drop into iCloud/OneDrive/Dropbox
  for sync. The format is documented and stable:
  [DATA-FORMAT](shared/spec/DATA-FORMAT.md).
- **Agent-facing CLI** — `taskly list|add|update|done|rm|search|mklist…`
  with stable `--json` output, fixed exit codes, and byte-level
  cross-platform parity pinned by a 61-case golden suite. Spec:
  [CLI-SPEC](shared/spec/CLI-SPEC.md).
- **Online updates (all platforms)** — silent check at launch plus a
  manual check in Settings; the backend verifies the signed
  [update manifest](shared/spec/UPDATE.md) (Ed25519) and downloads the
  artifact, the host installs it. macOS swaps the bundle in place,
  Windows swaps the install directory via a quit-and-install handoff,
  Linux downloads in-app and installs by extracting over the current
  folder.

## Honest gaps

- **The release packages don't include a standalone CLI binary yet** —
  the CLI runs from source today (see below); a packaged CLI distribution
  is on the roadmap.

## Install

Grab your build from
[Releases](https://github.com/turinglambdaai/taskly/releases/latest):

| Platform | Portable zip (in-app updates) | Installer |
|---|---|---|
| macOS Apple silicon | `taskly-<version>-macos-arm64.zip` | `taskly-<version>-macos-arm64.dmg` |
| macOS Intel | `taskly-<version>-macos-x64.zip` | `taskly-<version>-macos-x64.dmg` |
| Windows x64 | `taskly-<version>-windows-x64.zip` | `taskly-<version>-windows-x64.msi` |
| Windows ARM64 | runs the x64 build via Windows on ARM's x64 emulation | — |
| Linux x64 | `taskly-<version>-linux-x64.tar.gz` | native deb/rpm/AppImage planned (rivet#167) |

Every release carries a `SHA256SUMS` manifest and a signed
`update-manifest.json` — the in-app updater's feed. Portable zip
installs update themselves in place; MSI installs get pointed at the
releases page.

macOS builds are ad-hoc signed; if Gatekeeper complains on first launch,
run `xattr -cr /Applications/Taskly.app`.

Linux needs a GTK 4 desktop (unpack the tarball and run `RivetHost`;
GTK 4 and its system libraries are the only runtime dependencies —
everything else is bundled).

## CLI from source

```bash
git clone https://github.com/turinglambdaai/taskly.git
cd taskly
raco pkg install --auto --no-docs https://github.com/turinglambdaai/rivet.git
racket racket/taskly/cli.rkt add "买牛奶" --due tomorrow --json
racket racket/taskly/cli.rkt install-cli   # shim at ~/.local/bin/taskly
```

## Building from source

Racket CS 9.3+ plus the native toolchain of your desktop (Xcode/Swift on
macOS, CMake + GTK 4 headers on Linux, Windows App SDK on Windows):

```bash
raco rivet build        # generate clients, compile the core, build the host
raco test racket/       # 62 core contract tests
python3 shared/cli-golden/runner.py --binary scripts/taskly-cli.sh   # 61-case golden suite
```

## Architecture

```
┌─────────────────────────────┐            ┌────────────────────────────┐
│ First-party host            │            │ Racket CS core             │
│  SwiftUI · WinUI 3 · GTK 4  │◀── typed ──▶│  db · scheduling ·         │
│  render + interaction only  │  RPC (RVT1)│  validation · reminders    │
│  embedded Racket CS runtime │            │  agent CLI (same domain)   │
└─────────────────────────────┘            └────────────────────────────┘
```

One spec keeps every surface consistent: product behavior
([PRODUCT-SPEC](shared/spec/PRODUCT-SPEC.md)), data format, CLI contract,
design tokens, and the update contract — all under
[shared/spec/](shared/spec/). CI enforces the CLI contract with the
golden suite and byte-identical i18n on every push.

## License

[AGPL-3.0](LICENSE).
