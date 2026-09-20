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
                 RPC / State / Events
              ┌────────────┼────────────┐
              │            │            │
          Windows       macOS        Linux
          WinUI 3      SwiftUI      GTK4/libadwaita
```

The important boundary is not “one widget toolkit”. It is one product/domain
implementation with thin first-party platform shells.

## 3. What exists today

### Taskly

`main` currently has three independent product implementations:

- Windows: C# + WinUI 3
- macOS: Swift + SwiftUI
- Linux: Vala + GTK4/libadwaita

They share specs but duplicate application behavior.

### Rivet

Rivet currently provides:

- embedded Racket CS
- RVT1 RPC / Event / State / cancellation
- generated Swift and C++/WinRT clients
- Windows and macOS native hosts

Rivet does **not** currently provide:

- a Linux host
- a C# WinUI client (Taskly Windows is C#, while Rivet starts with C++/WinRT)
- record/DTO schema types (protocol v1 is primitives + nested lists)
- a cross-platform declarative native UI layer

Those are product-driven gaps. We will not pretend they are solved.

## 4. First vertical slice in this branch

The new `racket/taskly/` core owns:

- SQLite v4 creation/migrations and WAL behavior
- list/task repositories
- smart-view filtering and counts
- validation limits and stable Taskly error classification
- date parsing grammar
- config/path resolution
- add task
- edit task text
- set completed/incomplete
- delete task/list
- search
- Rivet wire adaptation and backend RPCs

The vertical slice is:

```text
open DB
  → load smart-list counts + sidebar lists + tasks
  → add task
  → edit task text
  → complete/uncomplete task
  → persist/reload
```

This is deliberately narrower than a full UI rewrite. It is enough to prove
whether the product boundary is correct.

## 5. Repository policy during migration

### `main`

- remains the releasable native implementation
- bug fixes and release hardening only
- no deletion of native business logic until a Rivet slice reaches parity

### `experiment/taskly-rivet`

- owns the migration
- may add Racket core and host adapters
- must keep DATA-FORMAT.md and CLI-SPEC.md compatibility
- may change Rivet only when Taskly demonstrates a concrete missing primitive

The existing native apps are behavioral and visual oracles. They are not dead
code until the corresponding Rivet path passes the acceptance gates below.

## 6. Rivet work Taskly should drive

Priority order is intentionally product-first:

1. **Record / DTO types**
   - Replace Taskly's temporary positional lists with generated `Task`,
     `TodoList`, `SmartCounts`, `Snapshot` native values.
   - This improves every serious Rivet application, not only Taskly.

2. **C# client/runtime surface for Windows**
   - Do not rewrite Taskly's proven WinUI UI in C++ just to satisfy Rivet.
   - Rivet should meet the product where the product already has a good native
     shell.

3. **Host lifecycle hooks**
   - startup/open database
   - clean shutdown
   - single-instance/app activation if Taskly needs it
   - deterministic event delivery to UI dispatchers

4. **Linux host decision**
   - GTK4/libadwaita adapter if first-party GNOME quality is practical
   - otherwise keep Linux native logic temporarily and do not block Windows/
     macOS commercial validation on framework ideology.

5. **Only then consider a declarative native UI DSL**
   - Build it from repeated Taskly UI patterns.
   - Do not design a complete widget universe in advance.

## 7. Acceptance gates

A native implementation can be replaced only when the Rivet path passes all
of these gates on that platform:

### Data

- opens existing schema-v4 databases in-place
- passes v0..v3 migration fixtures
- preserves signed ARGB values
- preserves config resolution and default-list behavior
- round-trips every task/list column

### Behavior

- smart lists match the current native reference
- add/edit/complete/delete/search match
- CLI golden tests match stdout/stderr/exit codes
- reminders observe the same task state

### Desktop quality

- IME works correctly
- keyboard navigation and focus are native-quality
- light/dark theme parity
- accessibility labels and semantics
- dialogs/menu/notifications are platform-native
- no visible Racket console/backend process

### Distribution

- one-click packaged application
- embedded exact Racket CS runtime
- signing/notarization supported
- clean upgrade path
- crash logs identify both native-host and Racket failures

## 8. Exit criteria / stop rules

The experiment is successful when Taskly can ship one production platform
through the shared Racket core with less product complexity than the current
three-way duplication.

Stop or narrow the experiment if any of these remain true after the vertical
slice:

- normal Taskly features require constant framework work before product work
- debugging across the bridge is materially worse than the duplicated native
  implementation
- startup/package size/latency becomes unacceptable for a small task app
- platform-native behavior requires bypassing Rivet so often that the bridge
  stops reducing complexity

A failed experiment is still valuable: the native `main` branch remains
intact, and Rivet receives concrete product-derived requirements rather than a
speculative API surface.

## 9. Immediate next implementation milestones

- M0 — shared Racket core + tests + Rivet backend contract (this branch)
- M1 — Rivet Record/DTO schema support
- M2 — Windows C# Rivet client + replace Taskly Windows repositories/services
- M3 — Windows vertical-slice UI parity using the existing WinUI screens
- M4 — macOS adapter and parity
- M5 — Linux host decision and implementation
- M6 — move CLI implementation to Racket and run one golden suite everywhere
- M7 — release engineering, signing, updater and commercial checklist

No milestone is allowed to delete the stable native reference before its own
parity gate is green.
