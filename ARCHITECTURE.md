# Taskly Architecture — Shared Racket Core + Native Platform Shells

> Status: **Experimental on `experiment/taskly-rivet`**
>
> Stable releases continue from `main` until a platform passes the migration
> gates in `docs/RIVET-MIGRATION.md`.

## Decision

Taskly will converge from three duplicated application implementations toward
one Racket application core connected to first-party native desktop shells
through Rivet.

The product rule is:

> Share product behavior; keep platform behavior native.

Racket owns behavior that must be identical everywhere. Native hosts own the
parts where platform fidelity is the feature.

## Ownership boundary

| Concern | Owner |
|---|---|
| SQLite schema/migrations, queries | Racket core |
| config and DB path resolution | Racket core |
| validation, date parsing, filtering | Racket core |
| task/list state transitions | Racket core |
| CLI semantics and exit classification | Racket core (migration target) |
| cross-host RPC/state/events | Rivet |
| WinUI / SwiftUI / GTK composition | native host |
| IME, keyboard, accessibility | native host |
| file dialogs, menus, notifications | native host |
| signing/package/update integration | native host + release tooling |

## Target data flow

```text
Native UI event
    │
    ▼
Generated Rivet client
    │
    ▼
Racket Taskly service
    │
    ├── validation / date / commands
    ├── SQLite v4 repository
    └── state + domain events
    │
    ▼
Rivet response/event
    │
    ▼
Native UI state
```

Native UI code must not contain a second implementation of Taskly business
rules after its migration milestone is complete.

## Repository layout

```text
taskly/
├── racket/
│   ├── info.rkt
│   ├── taskly/
│   │   ├── model.rkt
│   │   ├── errors.rkt
│   │   ├── clock.rkt
│   │   ├── paths.rkt
│   │   ├── config.rkt
│   │   ├── validation.rkt
│   │   ├── date-parser.rkt
│   │   ├── db.rkt
│   │   ├── service.rkt
│   │   ├── wire.rkt
│   │   └── backend.rkt
│   └── tests/
├── rivet.rktd
├── apps/
│   ├── windows/       # native reference shell during migration
│   ├── macos/         # native reference shell during migration
│   └── linux/         # native reference shell during migration
├── shared/spec/       # product contracts remain canonical
└── docs/RIVET-MIGRATION.md
```

## Compatibility invariants

The migration does not define a new product format.

- `PRAGMA user_version = 4`
- existing `.db` files open in-place
- WAL remains enabled
- default list remains `工作` / `📋` / signed ARGB `0xFF007AFF`
- task/list storage formats remain those in `shared/spec/DATA-FORMAT.md`
- CLI meanings and exit codes remain those in `shared/spec/CLI-SPEC.md`
- native visual behavior remains measured against the current applications

## Rivet dependency rule

Taskly is allowed to reveal missing Rivet capabilities. It is not allowed to
work around every missing capability inside Taskly until Rivet becomes an
opaque transport layer with product-specific hacks.

A capability belongs in Rivet when it is a reusable host/runtime concern. A
capability belongs in Taskly when it is Taskly product behavior.

Current framework gaps exposed by this product:

1. typed Record/DTO values
2. C# client support for the existing WinUI shell
3. Linux GTK host strategy
4. production lifecycle/diagnostic hooks needed by a commercial app

The temporary positional transport in `wire.rkt` exists only because RVT1 v1
has no Record type. It is a single replacement seam, not the long-term public
Taskly model.

## Migration safety

Do not delete or simplify the existing native implementation merely because a
Racket equivalent exists. Replacement happens platform by platform only after
contract tests and desktop-quality acceptance gates pass.

Do not build a general-purpose declarative UI toolkit before Taskly needs one.
If repeated native UI patterns justify an abstraction later, extract the
smallest reusable primitive from real Taskly code.

See `docs/RIVET-MIGRATION.md` for milestones and stop rules.
