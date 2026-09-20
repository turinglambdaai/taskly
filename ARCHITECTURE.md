# Taskly Architecture — Shared Racket Core + Native Platform Shells

> Status: **Experimental on `experiment/taskly-rivet`**
>
> Stable releases continue from `main` until a platform passes the migration
> gates in `docs/RIVET-MIGRATION.md`.

## Decision

Taskly is converging from three duplicated application implementations toward
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
| config and DB path resolution | Racket core (migration target; Windows shell still has transitional config code) |
| validation, date parsing, filtering | Racket core |
| task/list state transitions | Racket core |
| CLI semantics and exit classification | Racket core (migration target) |
| cross-host RPC/state/events, typed DTO generation | Rivet |
| Racket CS embedding/lifecycle | Rivet |
| WinUI / SwiftUI / GTK composition | native host |
| IME, keyboard, accessibility | native host |
| file dialogs, menus, notifications | native host |
| signing/package/update integration | native host + release tooling |

## Target data flow

```text
Native UI event
    │
    ▼
Platform application-backend port
    │
    ▼
Generated typed Rivet client
    │
    ▼
Embedded Racket Taskly service
    │
    ├── validation / date / commands
    ├── SQLite v4 repository
    └── state + domain events
    │
    ▼
Rivet response/event
    │
    ▼
Native presentation model / UI
```

Native UI code must not contain a second implementation of Taskly business
rules after its platform migration milestone is complete.

## Windows reference architecture

Windows is the first migration platform and now has an explicit reversible
boundary:

```text
MainViewModel + ReminderService
            │
      ITasklyBackend
       ┌────┴─────┐
       │          │
NativeTasklyBackend     RivetTasklyBackend
(reference/fallback)          │
       │                generated RivetAPI
 C# SQLite stack               │
                         EmbeddedRivetClient
                               │
                         rivet_native.dll
                               │
                         embedded Racket CS
                               │
                        Taskly Racket core
```

`UseRivetBackend=true` selects the Rivet path at compile time. A normal build
continues to compile the native fallback. CI builds both until the Windows
acceptance gates are complete.

The release target is **not** a hidden Racket child process. `ProcessRivetClient`
is a useful development transport; the production Windows path embeds Racket
CS in the Taskly process through Rivet's stable C ABI.

## Repository layout

```text
taskly/
├── racket/
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
│   │   ├── rivet-schema.rkt
│   │   └── backend.rkt
│   └── tests/
│       ├── core-test.rkt
│       ├── rivet-schema-test.rkt
│       └── dotnet-rivet-smoke/
├── rivet.rktd
├── apps/
│   ├── windows/       # first migration platform + native reference
│   ├── macos/         # native reference; next migration platform
│   └── linux/         # native reference; host strategy still pending
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
work around reusable host/runtime problems inside Taskly.

Capabilities Taskly has already driven into Rivet:

1. named Record/DTO schema types layered compatibly on RVT1
2. generated Swift, C++, and C# typed clients
3. managed `IRivetClient` runtime and development process transport
4. Windows in-process .NET embedding through `rivet_native.dll`
5. `raco rivet build-dotnet` for a self-contained Racket backend bundle
6. strict protocol-channel behavior (backend declarations may not pollute stdout)
7. generated C# support for ordinary domain names such as `Task`

Remaining framework/product gaps include:

- Linux GTK host strategy
- richer typed remote errors/diagnostics
- production crash/lifecycle instrumentation
- any declarative native UI abstraction that real Taskly repetition later justifies

RVT1 remains protocol version 1. Records are schema/codegen constructs encoded
as field-ordered RVT1 lists, so typed DTO support did not require a transport
version break.

## Migration safety

Do not delete or simplify the existing native implementation merely because a
Racket equivalent exists. Replacement happens platform by platform only after
contract tests and desktop-quality acceptance gates pass.

Do not build a general-purpose declarative UI toolkit before Taskly needs one.
If repeated native UI patterns justify an abstraction later, extract the
smallest reusable primitive from real Taskly code.

See `docs/RIVET-MIGRATION.md` for milestones and stop rules.
