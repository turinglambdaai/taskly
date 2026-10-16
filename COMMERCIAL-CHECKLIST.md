# Commercial Launch Checklist (engineering view)

The product sells on trust: people pay for a task manager that never loses a
task and feels native on their OS. This checklist is the engineering half of
going commercial; pricing/licensing decisions are the business half.

## 1. Identity & legal

- [ ] Decide distribution model per platform before 1.0 (Mac App Store vs
      direct + Paddle/FastSpring keys; Microsoft Store MSIX vs direct exe;
      Flatpak on Flathub). The DB/CLI contract stays identical either way.
- [x] License model decided: the desktop core stays open source under
      AGPL-3.0 — free to use and fork, copyleft blocks closed-source forks.
      Commercial surfaces (the iOS/iPadOS client and the sync service) live
      in separate private repos under their own terms. Already-published
      history stays under the license it was released under.
- [ ] EULA + privacy policy: the app is fully offline/local-first — say so.
      No telemetry in v1 (crash reporting opt-in only, see §4).
- [ ] Trademark search on "Taskly" in target markets before paid ads.

## 2. Signing & notarization (non-negotiable for paid desktop software)

- [ ] macOS: Apple Developer Program, Developer ID Application cert,
      hardened runtime, notarization (staple). Gatekeeper is the #1 refund
      trigger; the in-app updater (signed manifests, in-place swap) is
      already shipped — only the signing identity is missing.
- [ ] Windows: code-signing cert (EV/OV), sign the MSI AND the exe.
      SmartScreen reputation builds with consistent signing over time.
- [ ] Linux: distro packaging is GitHub-Releases-only today (deb/rpm/
      AppImage/tar.gz); revisit store/Flathub verification only if that
      channel decision changes.

## 3. Monetization engineering hooks (build when the model is chosen)

- [ ] License-key validation: offline Ed25519-signed keys (no phone-home).
- [ ] Free tier boundary (suggested: 3 lists / unlimited tasks) — keep the
      entitlement check in one module per platform, easily relaxed for sales.
- [ ] Trial: full features, 14 days, local clock tamper-tolerant check.
- [ ] Store builds (MAS/MSIX) receive Store licensing APIs instead of keys.

## 4. Quality gates (blocking for 1.0)

- [ ] CI green on all three platforms: `ci.yml` (i18n/release-metadata
      preflight + Racket core contract tests + golden CLI suite + GTK4,
      SwiftUI, and WinRT host builds with boot smoke).
- [ ] Cross-platform DB conformance: open a DB written by each platform in
      each other platform (fixture in `shared/`).
- [ ] Golden CLI suite: shared fixture lives in `shared/cli-golden/` (63
      cases, exact stdout/stderr/exit). Wired into `ci.yml` against the
      source-level CLI shim on the Linux runner — running the same fixture
      against the packaged per-platform binaries is still pending.
- [ ] Crash reporting: opt-in Sentry/crashpad per platform; P1 crash < 0.1%
      sessions for two consecutive betas.
- [ ] Reminder reliability soak test: notifications fire while app runs
      across midnight/local-timezone changes; permission-denied never
      crashes (regression: 0.6.1 macOS incident).

## 5. Release engineering

- [ ] Single version source per app + one CHANGELOG entry per release.
- [ ] `release.yml`: tag → build all platforms → sign the update manifest
      (Ed25519) → upload artifacts → GitHub Release (store submissions when
      a store model lands).
- [ ] Auto-update smoke: N → N+1 in-place update keeps `~/.taskly` intact
      (test on all three OSes with a real user DB copy — the OTA path is
      already exercised every release; keep the check deliberate).
- [ ] Rollback plan: keep previous version downloadable; DB migrations are
      append-only so downgrades never lose data.

## 6. Support & docs

- [ ] Landing/docs site already exists (`docs/`, GitHub Pages) — add:
      data-format page (transparency = trust) and a CLI reference (agent
      users are a paying niche).
- [ ] In-app "Where is my data?" page pointing at `~/.taskly/tasks.db`.
- [ ] Support inbox + refund policy wired into the store checkout.
