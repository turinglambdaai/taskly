# Taskly Architecture — Shared Racket Core + Native Platform Shells

> Status: **Mainline** — the Rivet rebuild is the product line (single `main`
> branch); all three desktop hosts ship from it. The migration history lives
> in git (the pre-rewrite native line ends at commit `51c9c1c`).

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
| config and DB path resolution | Racket core |
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
│       └── cli-update-test.rkt
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
2. generated Swift and C++ typed clients
3. strict protocol-channel behavior (backend declarations may not pollute stdout)
4. release machinery this product consumes directly: signed update
   manifests, DMG/MSI/Linux-package output, SBOM + notices

Remaining framework/product gaps include:

- richer typed remote errors/diagnostics
- production crash/lifecycle instrumentation
- any declarative native UI abstraction that real Taskly repetition later justifies

RVT1 remains protocol version 1. Records are schema/codegen constructs encoded
as field-ordered RVT1 lists, so typed DTO support did not require a transport
version break. (An early .NET client path — C# codegen, `rivet_native.dll`,
`raco rivet build-dotnet` — existed during the migration and was dropped when
the Windows host settled on C++/WinRT; see the rivet PR #50/#51 discussion.)

## Migration safety

Hosts stay presentation-only: product behavior lives in the Racket core.
Do not build a general-purpose declarative UI toolkit before Taskly needs one.
If repeated native UI patterns justify an abstraction later, extract the
smallest reusable primitive from real Taskly code.

Missing Rivet capabilities surface as upstream issues/PRs against
`turinglambdaai/rivet` as product work hits them; the historical backlog of
taskly-driven framework work (and its resolution record) is in git history
and the rivet issue tracker.
