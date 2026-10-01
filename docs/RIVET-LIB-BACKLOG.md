# Rivet Library Backlog — discovered by the Taskly pilot

> Feed-back loop: Taskly is the first commercial acceptance test for Rivet.
> Every product need that forces framework work lands here as a concrete,
> prioritized library improvement. Items move to the Rivet repo when picked
> up; the Taskly commit that discovered each item is referenced.

## Status 2026-09-28

- PR #60 (commercial distribution + system services) **merged** — update
  manifests, WiX MSI packaging, Ed25519 signing, system-service adapters,
  settings, logging/crash APIs are now part of rivet main.
- **Direction decision**: Rivet's Windows host is C++/WinRT + in-process
  Racket CS. A .NET/C# client surface was evaluated (PR #50/#51) and
  rejected as a parallel runtime — the same decision applies to Taskly's
  Windows shell: the host is C++/WinRT, not C#.

## P0 — blocks the Windows product slice

### 1. Taskly Windows host = C++/WinRT (in progress)
- The old C# WinUI app cannot attach a Rivet backend (no .NET client
  surface, by design). Taskly's Windows app is being rebuilt on the rivet
  scaffold: windows/RivetHost.vcxproj (C++/WinRT) + the Racket backend via
  GeneratedBackend.hpp.
- Ask: none to rivet yet — the scaffold + `raco rivet build` work as-is.
- First Taskly need that forces a rivet change becomes a PR.

## P1 — needed by the Taskly Racket backend

### 2. Named records / Optional / nested record types in rivet/backend
- Discovered: 09-28 rebuild — current rivet main's type system has only
  primitives (Void/Bool/Int64/String/Bytes/List). The Taskly Racket core
  (racket/taskly/, ported from the Sep 21 pilot) is written against the
  named-record API: define-record, Optional, nested (List Record), record
  values in RPC results and State.
- Ask: port the named-record/Optional schema layer into rivet/backend
  (RVT1 wire format unchanged: records encode as field-ordered lists;
  Optional delegates to inner). A reference implementation exists in the
  Taskly pilot's history (racket/taskly/rivet-schema.rkt era, taskly
  branch experiment/taskly-rivet ~Sep 21).

### 3. Single-entity lookup RPC (`get-task-by-id`)
- Discovered: 09-28 merge (RivetTasklyBackend.GetTaskByIdAsync).
- Current workaround: `LoadSnapshotAsync("all", showCompleted: true)` +
  client-side filter — correct but loads every task for one lookup.
- Ask: a typed `get-task(id)` RPC in the RVT1 contract (Racket side +
  codegen), following the existing named-record pattern.

### 4. Diagnostics that attribute failures to native host vs Racket
- Discovered: migration doc acceptance gate + the Sep 21 debugging slog
  (crash phases isolated manually via console hosts).
- Ask: crash/exit logs that tag the failing layer (Racket, C ABI bridge,
  native client), so a Taskly crash report answers "which side" without a
  repro. Included in the doc's distribution gate.

## P2 — product quality, next quarter

### 5. Linux host strategy
- Discovered: migration doc §3. Taskly's Linux build is GTK4 native today.
- Ask: a supported story for in-process embedding (or a declared
  out-of-process daemon contract) on Linux.

### 6. Startup / package size / latency budgets with measurement hooks
- Discovered: migration doc §8 stop-rules reference these thresholds but
  rivet ships no measurement tooling.
- Ask: documented budgets + a `raco rivet measure` style command that
  reports startup time, bundle size, and per-RPC latency for a host app.

### 7. Cross-bridge debugging experience
- Discovered: migration doc §8 stop-rule — "debugging across the bridge is
  materially worse than duplicated native logic" is a declared stop
  condition, and the Sep 21 slog confirmed it.
- Ask: structured error propagation across RVT1 (Racket exceptions with
  stack context surviving to the native client) and a verbose-trace mode in
  the runtime.

## P3 — long-term

### 8. Cross-platform declarative UI layer
- Not blocking the Windows slice; would only matter after M5. Keep on the
  roadmap; no ask yet.

### 9. Protocol evolution beyond RVT1 v1
- M1 added named Record/DTO schemas without breaking RVT1 v1 — the right
  pattern. Continue additive evolution; keep the v1 decoder forever.

## Already delivered by Taskly (for the changelog)

- Named Record/DTO schema support design (pilot; awaiting port to rivet
  main — see backlog item 2)
- Swift / C++ typed client generation
- Managed RVT1 codec, async runtime
- `ProcessRivetClient` for development/testing
- Windows C ABI around the embedded Racket CS runtime
- `raco rivet build-dotnet` design (superseded by the C++/WinRT host
  direction; the dotnet path was evaluated and rejected — PRs #50/#51)
- Strict stdout/protocol-channel behavior
- C# codegen that handles domain types named `Task`

## Status 2026-10-01 — filed upstream

| Item | Rivet issue |
|---|---|
| 2 · named records / Optional / nested types | ✅ 已由 rivet main 解决（PR #72 + #78）；[#92](https://github.com/turinglambdaai/rivet/issues/92) 已附应用侧验证后关闭（56 测试对 linked main 全绿） |
| 4 · layer-attributed diagnostics | [#93](https://github.com/turinglambdaai/rivet/issues/93) |
| 7 · cross-bridge debugging | [#94](https://github.com/turinglambdaai/rivet/issues/94) |
| 5 · Linux host strategy | [#95](https://github.com/turinglambdaai/rivet/issues/95) |
| 6 · measure / budgets tooling | [#96](https://github.com/turinglambdaai/rivet/issues/96) |

Item 3 (single-entity lookup) is application-level work once item 2 lands
— it does not need its own rivet issue. Application-side workarounds stay
documented in place until the issues close.

Post-script: `recovered/taskly-m1` never needed recovering — rivet main
landed M1 via #72/#78, and this repo's `racket/taskly/rivet-schema.rkt`
turned out to be plain app-level schema declarations on the library API
(not a shim), verified by 56 green core tests against linked main.
Item 3 (single-entity RPC) is now unblocked as ordinary application work.

## Addendum 2026-10-01 — distribution automation (winget)

Discovered while wiring 5 products (brainfuel, movebit, podlens, payback,
hackdigest) to winget: each repo now carries a copy-pasted
`.github/workflows/winget.yml` + `packaging/winget/` seed manifests
(schema 1.6.0, metadata extracted with `komac analyze --hash`); first
submissions are open as microsoft/winget-pkgs #444829–#444833. Rivet apps
get their MSI from `raco rivet release`, so the winget surface applies to
every future rivet app (taskly rivet line, fulcrum, the
brainfuel/movebit/syncpilot/pdfgist rewrites).

### 10. Winget distribution scaffold in rivet — filed upstream [#121](https://github.com/turinglambdaai/rivet/issues/121)
- The winget workflow + seed-manifest template is identical across
  products except identifier / installers-regex / descriptions. Each new
  rivet app re-copies it by hand.
- Ask: `raco rivet winget-init` writing the workflow + seed manifests from
  `rivet.rktd` metadata, or `raco rivet release` emitting winget seed
  manifests alongside the MSI. Needs a publisher field (see 10a) to render
  `AppsAndFeaturesEntries` faithfully.

### 10a. MSI Manufacturer defect — filed upstream
- `rivet-cli/installer.rkt` sets WiX `Manufacturer` to the reverse-DNS
  identifier → ARP shows `site.jrtx.podlens` as podlens's publisher.
- Filed: [#112](https://github.com/turinglambdaai/rivet/issues/112) —
  `Manufacturer := publisher ?? display-name`.
