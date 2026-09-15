# Taskly for Linux (Vala + GTK4/libadwaita)

Native GNOME-platform app: **Vala** — the GNOME project's first-party language
that compiles to plain C/GObject (no VM, no runtime; the binary links only C
libraries: libgtk-4, libadwaita-1, libsqlite3, libnotify, glib). Build system
is meson, the GNOME standard. The binary is dual-mode — `taskly` with no
arguments opens the native window; any argument routes to the agent CLI
(contract-identical to the macOS/Windows ports), before any GTK
initialization.

## Build

Requires valac, meson, and the GTK4/libadwaita development packages:

```bash
# Debian/Ubuntu
sudo apt install valac meson libgtk-4-dev libadwaita-1-dev \
  libsqlite3-dev libnotify-dev pkg-config
# Fedora
sudo dnf install vala meson gtk4-devel libadwaita-devel \
  sqlite-devel libnotify-devel

cd apps/linux
meson setup build
meson compile -C build
meson test -C build        # contract tests (schema, date parser, i18n, CLI JSON)

./build/taskly list --json
./build/taskly                             # GUI
```

## Package

- Flatpak manifest: `flatpak/app.taskly.Taskly.yml` (org.gnome.Sdk ships
  valac + meson)
- Desktop entry: `resources/taskly.desktop`; icon: `resources/taskly.svg`
- Binary links system libsqlite3 only — no bundled SQLite

## Layout

| Path | Contents |
|---|---|
| `src/taskly.vala` | Entry: CLI routing before GTK init + Adw.Application |
| `src/database.vala` | Schema v4 + contract queries + conformance-ready helpers |
| `src/dateparser.vala` | Date/time grammar contract (`--due` syntax) |
| `src/cli.vala`, `src/clijson.vala`, `src/cliinstaller.vala` | Agent CLI, byte-compatible JSON writer, install-cli |
| `src/reminder.vala` | Due reminders via libnotify (freedesktop notifications) |
| `src/ui.vala`, `src/dialogs.vala` | GTK4/libadwaita window + modal editors |
| `src/i18n.vala` | Bilingual tables from `resources/i18n/*.json` (synced single source) |
| `tests/core-test.vala` | Contract tests (`meson test`) |

## Status / known deltas vs 0.6.4

- Feature-complete per `shared/spec/PRODUCT-SPEC.md` except: list edit and
  task full-editing live in modal dialogs (right-click menus land with a
  later popover pass); task-row inline text editing is dialog-based.
- Quick-add adopts the CLI date semantics (pure-date intent clears the time —
  the 0.6.x GUI quirk is fixed).
- Verified: full native compile + link (GTK4/libadwaita toolchain), contract
  tests green, CLI end-to-end smoke with `--db` isolation. Linux CI job runs
  the same on ubuntu-latest.
