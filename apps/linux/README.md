# Taskly for Linux (Rust + GTK4/libadwaita)

Native GNOME-platform app: GTK 4 + libadwaita via gtk4-rs, bundled SQLite via
rusqlite (no system SQLite dependency). The binary is dual-mode — `taskly`
with no arguments opens the native window; any argument routes to the agent
CLI (contract-identical to the macOS/Windows ports).

## Build

Requires Rust 1.75+ and the GTK4/libadwaita development packages:

```bash
# Debian/Ubuntu
sudo apt install build-essential pkg-config libgtk-4-dev libadwaita-1-dev
# Fedora
sudo dnf install rust cargo gtk4-devel libadwaita-devel

cd apps/linux
cargo build --release
cargo test          # contract tests (schema, date parser, CLI JSON)
./target/release/taskly            # GUI
./target/release/taskly list --json
```

## Package

- Flatpak manifest: `flatpak/app.taskly.Taskly.yml`
- Desktop entry: `resources/taskly.desktop`
- Portable binary: `cargo build --release` output (bundled SQLite; only
  GTK4/libadwaita are dynamic)

## Layout

| Path | Contents |
|---|---|
| `src/main.rs` | Dual-mode entry (CLI before GTK init) |
| `src/db.rs` | Schema v4 + contract queries + repositories + unit tests |
| `src/date_parser.rs` | Date/time grammar contract + tests |
| `src/cli.rs`, `src/cli_installer.rs` | Agent CLI + install-cli |
| `src/reminder.rs` | Due reminders via the desktop notification daemon |
| `src/ui.rs`, `src/dialogs.rs` | GTK4/libadwaita window + modal editors |
| `resources/i18n/` | zh/en JSON synced from `shared/i18n` (CI-verified) |

## Status / known deltas vs 0.6.4

- Feature-complete per `shared/spec/PRODUCT-SPEC.md` except: list edit and
  task full-editing live in modal dialogs (right-click menus land with the
  GTK popover pass); task-row inline text editing is dialog-based on Linux.
- Quick-add adopts the CLI date semantics (pure-date intent clears the time —
  the 0.6.x GUI quirk is fixed).
- First build must happen on a Linux machine/CI runner (CI:
  `.github/workflows/native.yml`, ubuntu job runs `cargo test` + build).
