# Taskly

A focused, native task manager. One product, one SQLite file, one agent CLI —
implemented natively per platform.

**English** · [中文](README.zh-CN.md)

## Native, not cross-platform

Taskly v1 is a full native rewrite of the Avalonia-based 0.6.x app. Each
desktop gets its platform's first-party UI stack — no embedded web views, no
foreign toolkits, no upstream UI regressions (the Windows IME duplication and
macOS notification crashes of 0.6.x were the last straw).

| Platform | Stack | Status | Build |
|---|---|---|---|
| macOS 14+ | Swift 6 + SwiftUI | ✅ build + 24 tests + CLI smoke verified | [apps/macos](apps/macos) |
| Windows 10+ | WinUI 3 (Windows App SDK) + .NET 10 | source complete, CI build | [apps/windows](apps/windows) |
| Linux | Vala + GTK4 / libadwaita (compiles to C/GObject) | ✅ native build + contract tests verified | [apps/linux](apps/linux) |
| iOS / iPadOS (next) | reuses the macOS SwiftUI codebase | planned | — |
| Android (next) | Kotlin + Jetpack Compose | planned | — |

Architecture rationale: [ARCHITECTURE.md](ARCHITECTURE.md). The frozen
Avalonia 0.6.x implementation lives in `src/Taskly` as a behavioral reference
until the native 1.0 GA.

## What ships in every app

- **Reminders-style UI** — smart views (Today / Planned / All / Completed),
  custom lists with emoji icons and colors, quick add with natural-language
  dates (`@10am`, `+1d`, `tomorrow`), due-task OS notifications, bilingual
  zh/en (live switch), warm Anthropic palette, light/dark.
- **One data file** — your tasks live in a single SQLite file
  (`~/.taskly/tasks.db`, WAL) you can drop into iCloud/OneDrive/Dropbox for
  sync. The format is documented and stable: [DATA-FORMAT](shared/spec/DATA-FORMAT.md).
- **Agent CLI in the same binary** — `taskly list|add|update|done|rm|search|…`
  with `--json`, stable exit codes, and headless operation. Spec:
  [CLI-SPEC](shared/spec/CLI-SPEC.md). Install via the app menu (Tools ▸
  Install Command Line Tool) or `taskly install-cli`.

## For developers

```
taskly/
├── apps/macos|windows|linux/   native apps (each with its own build system)
├── shared/spec/                the contract: product · data · CLI · design tokens
├── shared/i18n/                zh/en single source (CI verifies platform copies)
├── scripts/                    sync-i18n and CI helpers
├── src/Taskly/                 legacy Avalonia app (frozen reference)
└── .github/workflows/          ci.yml (legacy) · native.yml (three platforms)
```

The three apps share **no code**. They share the contract (`shared/spec/`),
and CI enforces it: identical CLI JSON/exit codes, byte-identical i18n, one
DB schema (user_version 4) with lockstep migrations.

### Build

```bash
# macOS
cd apps/macos && swift build && swift test
scripts/make-app.sh            # Taskly.app

# Windows
dotnet build apps/windows/Taskly/Taskly.csproj -c Release

# Linux
cd apps/linux && meson setup build && meson compile -C build && meson test -C build
```

## Requirements

- macOS: 14 Sonoma or later (Apple Silicon + Intel)
- Windows: 10 19041+ / 11
- Linux: any GTK4/libadwaita desktop (GNOME 44+ recommended)

## License

Apache-2.0 for the current public code; the commercial licensing model is
being decided — see [COMMERCIAL-CHECKLIST](COMMERCIAL-CHECKLIST.md).
