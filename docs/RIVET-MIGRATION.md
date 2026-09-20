# Taskly × Rivet Migration Architecture

> Branch: `experiment/taskly-rivet`
>
> Goal: make Taskly the first commercial acceptance test for Rivet without
> destabilizing the current native product on `main`.

## 1. Product rule

Taskly drives the framework; the framework does not drive Taskly.

We are not rewriting Taskly because Racket is preferred. We are removing
business-logic duplication where a shared implementation has measurable value:
SQLite schema/migrations, validation, date parsing, filtering, configuration,
CLI semantics, state transitions, and agent-facing behavior.

Native UI remains the reference for platform feel, accessibility, IME,
keyboard behavior, menus, notifications, dialogs and packaging.

## 2. Target architecture

```text
                         Taskly
                           │
                  Racket application core
          ┌────────────────┼────────────────┐
          │                │                │
       SQLite v4        commands        app state
          │                │                │
          └────────────── Rivet ────────────┘
                           │
                 typed RPC / State / Events
              ┌────────────┼────────────┐
              │            │            │
          Windows       macOS        Linux
          WinUI 3      SwiftUI      GTK4/libadwaita
```

The important boundary is not “one widget toolkit”. It is one product/domain
implementation with thin first-party platform shells.

## 3. Current implementation status

### Taskly shared core

The experimental branch now has one Racket implementation of:

- SQLite schema v4, migrations, WAL and queries
- task/list domain records
- validation and stable error classification
- date parsing grammar
- config/path primitives
- smart views and counts
- add/update/move/complete/delete/search behavior
- typed `Task`, `TodoList`, `SmartCounts`, and `Snapshot` Rivet DTOs
- a typed Rivet backend with stdio and embedded entry points

Core tests run on Windows, macOS and Linux.

### Rivet capabilities driven by Taskly

Taskly has already caused reusable framework work to land on
`feature/taskly-records`:

- named Record/DTO schema support without changing RVT1 v1
- Swift, C++ and C# typed client generation
- managed `IRivetClient`, RVT1 codec and async runtime
- `ProcessRivetClient` for development/testing
- stable Windows C ABI around the existing embedded Racket runtime
- `EmbeddedRivetClient` for in-process .NET hosts
- `raco rivet build-dotnet` to generate API + `core.zo` + Racket runtime + native bridge
- strict stdout/protocol-channel behavior
- C# codegen that handles domain types named `Task`

Rivet still does not provide a Linux Taskly host strategy or a general
cross-platform declarative UI layer. Neither blocks the Windows product slice.

## 4. Windows migration architecture

The existing C# WinUI screens were deliberately preserved. They now depend on
an application port instead of directly depending on SQLite repositories:

```text
MainViewModel / ReminderService
              │
        ITasklyBackend
         ┌────┴─────┐
         │          │
NativeTasklyBackend  RivetTasklyBackend
   reference             │
                         ▼
                  generated RivetAPI
                         │
                  EmbeddedRivetClient
                         │
                   rivet_native.dll
                         │
                 embedded Racket CS
                         │
                  Taskly Racket core
```

Normal builds keep `NativeTasklyBackend`. `UseRivetBackend=true` defines
`TASKLY_RIVET` and selects `RivetTasklyBackend`. CI builds both until parity is
proven.

This is intentionally reversible. The native adapter is a behavioral oracle,
not an architecture we plan to maintain forever after migration.

## 5. What has been proven by CI

### M0 — shared Racket core — complete

- Racket core compiles/tests on Windows, macOS and Linux
- schema v4 behavior is exercised with real SQLite
- add/edit/complete/list operations are covered

### M1 — typed Rivet contract — complete

- Record DTOs replace the old positional Taskly wire layer
- nested Optional/List/Record values validate on both sides
- generated Swift/C++/C# DTO clients compile
- RVT1 remains protocol v1

### M2 — Windows C# runtime path — implementation complete, product build gate active

Proven independently:

- C# process client → RVT1 → real Taskly Racket backend → SQLite end-to-end
- full task/list editing round-trips across C#/Racket
- `raco rivet build-dotnet` builds a Windows embedded runtime bundle
- .NET starts Racket CS **in process** and successfully calls RPC and shared state
- ordinary WinUI build remains green after `ITasklyBackend` extraction

The final M2 gate is the Taskly dual-mode WinUI CI: Native fallback and
`UseRivetBackend=true` must both build with the exact pinned Rivet commit and
validate the packaged runtime layout.

## 6. Repository policy during migration

### `main`

- remains the releasable native implementation
- bug fixes and release hardening only
- no deletion of native business logic until a Rivet slice reaches parity

### `experiment/taskly-rivet`

- owns the migration
- keeps exact Rivet commit pins in CI
- must keep DATA-FORMAT.md and CLI-SPEC.md compatibility
- changes Rivet only when Taskly demonstrates a concrete reusable missing primitive

The existing native apps are behavioral and visual oracles. They are not dead
code until the corresponding Rivet path passes the acceptance gates below.

## 7. Acceptance gates

A native implementation can be replaced only when the Rivet path passes all
of these gates on that platform.

### Data

- opens existing schema-v4 databases in-place
- passes v0..v3 migration fixtures
- preserves signed ARGB values
- preserves config resolution and default-list behavior
- round-trips every task/list column

### Behavior

- smart lists match the current native reference
- add/edit/move/complete/delete/search match
- CLI golden tests match stdout/stderr/exit codes
- reminders observe the same task state
- concurrent UI operations do not corrupt bridge/runtime state

### Desktop quality

- IME works correctly
- keyboard navigation and focus are native-quality
- light/dark theme parity
- accessibility labels and semantics
- dialogs/menu/notifications are platform-native
- no visible Racket console/backend process
- startup/shutdown does not hang or leave runtime threads behind

### Distribution

- one-click packaged application
- embedded exact Racket CS runtime
- signing/notarization supported
- clean upgrade path
- crash logs identify both native-host and Racket failures
- native runtime dependencies are present in the installed output

## 8. Exit criteria / stop rules

The experiment is successful when Taskly can ship one production platform
through the shared Racket core with less product complexity than the current
three-way duplication.

Stop or narrow the experiment if any of these remain true after the vertical
slice:

- normal Taskly features require constant framework work before product work
- debugging across the bridge is materially worse than duplicated native logic
- startup/package size/latency becomes unacceptable for a small task app
- platform-native behavior requires bypassing Rivet so often that the bridge
  stops reducing complexity

A failed experiment remains reversible because `main` and the native backend
reference are intact.

## 9. Milestones

- **M0 — shared Racket core + tests:** complete
- **M1 — Rivet Record/DTO schema support:** complete
- **M2 — Windows C# client + in-process Racket runtime + backend port:** implementation complete; dual-mode Taskly build is the remaining gate
- **M3 — Windows runtime/UI parity:** next; run the existing WinUI product against the Rivet backend and remove behavioral differences, not the fallback yet
- **M4 — macOS adapter and parity:** after Windows demonstrates product value
- **M5 — Linux host decision and implementation:** after Windows/macOS evidence
- **M6 — move CLI implementation to Racket and run one golden suite everywhere**
- **M7 — release engineering, signing, updater, crash diagnostics and commercial checklist**

No milestone is allowed to delete the stable native reference before its own
parity gate is green.
