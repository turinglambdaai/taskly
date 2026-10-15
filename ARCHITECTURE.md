# Taskly Architecture — Shared Racket Core + Native Platform Shells

> Status: **Mainline** — the Rivet rebuild is the product line (single `main` branch).
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

## Windows host

Historical note: an earlier version of this section diagrammed the
pre-rewrite C#/WinUI host with a reversible backend boundary
(`ITasklyBackend`, `NativeTasklyBackend`, `RivetTasklyBackend`,
`UseRivetBackend=true`) — that implementation no longer exists in the
repository. Windows ships the C++/WinRT host in `windows/` with no native
fallback backend to select.

What the old section got right and still holds: the release target is
**not** a hidden Racket child process. The development process transport is
useful for debugging; the production path on every host — Windows included —
embeds Racket CS in the Taskly process through Rivet's stable C ABI.

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
│   │   ├── backend.rkt      # Rivet backend entry (typed RPC surface)
│   │   ├── cli.rkt          # agent CLI (taskly list|add|…)
│   │   ├── updater.rkt      # update feed client (shared/spec/UPDATE.md)
│   │   └── version.rkt
│   └── tests/
│       ├── core-test.rkt
│       ├── backend-test.rkt
│       ├── backend-wire-test.rkt
│       ├── rivet-schema-test.rkt
│       ├── updater-test.rkt
│       ├── cli-update-test.rkt
│       └── dotnet-rivet-smoke/
├── macos-host/        # SwiftUI host (arm64 + x64)
├── windows/           # C++/WinRT host (x64)
├── linux/             # GTK4 host (x64 + arm64; deb/rpm/AppImage/tar.gz)
├── shared/            # spec contracts, i18n, emoji, cli-golden
├── scripts/           # release tooling (preflight, manifest signing, keys)
├── assets/            # icons and branding
├── docs/              # product site + handoff/benchmark/migration notes
├── rivet.rktd
└── rivet-schema.json
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
