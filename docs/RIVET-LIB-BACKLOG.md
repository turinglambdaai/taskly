# Rivet Library Backlog — discovered by the Taskly pilot

> Feed-back loop: Taskly is the first commercial acceptance test for Rivet.
> Every product need that forces framework work lands here as a concrete,
> prioritized library improvement. Items move to the Rivet repo when picked
> up; the Taskly commit that discovered each item is referenced.

## P0 — blocks the Windows product slice

### 1. In-process embedding stability on WinUI hosts
- Discovered: Sep 21 experiment (commits ea9752d / 03ec8d9 / 833826b on
  `experiment/taskly-rivet`) — embedding the Racket CS runtime into the
  WinUI 3 process crashed in phases that were never fully converged.
- Impact: blocks M3 (Windows runtime/UI parity) — the single remaining gate
  for the Windows slice.
- Ask: a reproducible minimal host sample (console + WinUI) plus a
  root-cause writeup of the crash signature; if fixed, Taskly flips
  `UseRivetBackend=true` immediately.

## P1 — needed by the merged product UI

### 2. Single-entity lookup RPC (`get-task-by-id`)
- Discovered: 09-28 merge (RivetTasklyBackend.GetTaskByIdAsync).
- Current workaround: `LoadSnapshotAsync("all", showCompleted: true)` +
  client-side filter — correct but loads every task for one lookup.
- Ask: a typed `get-task(id)` RPC in the RVT1 contract (Racket side +
  codegen), following the existing named-record pattern.

### 3. Diagnostics that attribute failures to native host vs Racket
- Discovered: migration doc acceptance gate + the Sep 21 debugging slog
  (crash phases had to be isolated manually via console hosts).
- Ask: crash/exit logs that tag the failing layer (Racket, C ABI bridge,
  .NET client), so a Taskly crash report answers "which side" without a
  repro. Included in the doc's distribution gate.

## P2 — product quality, next quarter

### 4. Linux host strategy
- Discovered: migration doc §3 ("Rivet still does not provide a Linux
  Taskly host strategy"). Taskly's Linux build is GTK4 native today.
- Ask: a supported story for in-process embedding (or a declared
  out-of-process daemon contract) on Linux.

### 5. Startup / package size / latency budgets with measurement hooks
- Discovered: migration doc §8 stop-rules reference these thresholds but
  Rivet ships no measurement tooling.
- Ask: documented budgets + a `raco rivet measure` style command that
  reports startup time, bundle size, and per-RPC latency for a host app.

### 6. Cross-bridge debugging experience
- Discovered: migration doc §8 stop-rule — "debugging across the bridge is
  materially worse than duplicated native logic" is a declared stop
  condition, and the Sep 21 slog confirmed it.
- Ask: structured error propagation across RVT1 (Racket exceptions with
  stack context surviving to the .NET client) and a verbose-trace mode in
  the runtime.

## P3 — long-term

### 7. Cross-platform declarative UI layer
- Discovered: migration doc §3. Not blocking the Windows slice; would only
  matter after M5. Keep on the roadmap; no ask yet.

### 8. Protocol evolution beyond RVT1 v1
- Discovered: M1 added named Record/DTO schemas without breaking RVT1 v1 —
  the right pattern. Continue additive evolution; keep the v1 decoder
  forever for compatibility.

## Already delivered by Taskly (for the changelog)

- Named Record/DTO schema support (no RVT1 v1 change)
- Swift / C++ / C# typed client generation
- Managed `IRivetClient`, RVT1 codec, async runtime
- `ProcessRivetClient` for development/testing
- Windows C ABI around the embedded Racket CS runtime
- `EmbeddedRivetClient` for in-process .NET hosts
- `raco rivet build-dotnet` (API + core.zo + runtime + native bridge)
- Strict stdout/protocol-channel behavior
- C# codegen that handles domain types named `Task`
