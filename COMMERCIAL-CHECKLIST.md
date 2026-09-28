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
      hardened runtime, notarization (staple), Sparkle-style updater or
      Velopack-style delta updates. Gatekeeper is the #1 refund trigger.
- [ ] Windows: code-signing cert (EV/OV), sign the installer AND the exe;
      Velopack releases already support signing + delta updates. SmartScreen
      reputation builds with consistent signing over time.
- [ ] Linux: Flathub verification (repo ownership check).

## 3. Monetization engineering hooks (build when the model is chosen)

- [ ] License-key validation: offline Ed25519-signed keys (no phone-home).
- [ ] Free tier boundary (suggested: 3 lists / unlimited tasks) — keep the
      entitlement check in one module per platform, easily relaxed for sales.
- [ ] Trial: full features, 14 days, local clock tamper-tolerant check.
- [ ] Store builds (MAS/MSIX) receive Store licensing APIs instead of keys.

## 4. Quality gates (blocking for 1.0)

- [ ] CI green on all three platforms: `native.yml` (builds + Swift tests +
      Rust tests + CLI golden smoke + i18n parity).
- [ ] Cross-platform DB conformance: open a DB written by each platform in
      each other platform (fixture in `shared/`), including a v0.6.x DB.
- [ ] Golden CLI suite: identical argv → identical JSON/exit codes on all
      three platforms (extend the macOS smoke into a shared fixture).
- [ ] Crash reporting: opt-in Sentry/crashpad per platform; P1 crash < 0.1%
      sessions for two consecutive betas.
- [ ] Reminder reliability soak test: notifications fire while app runs
      across midnight/local-timezone changes; permission-denied never
      crashes (regression: 0.6.1 macOS incident).

## 5. Release engineering

- [ ] Single version source per app + one CHANGELOG entry per release.
- [ ] `release-native.yml`: tag → build all platforms → sign → upload
      artifacts → GitHub Release + store submissions.
- [ ] Auto-update smoke: 0.6.x → 1.0 upgrade path keeps `~/.taskly` intact
      (test on all three OSes with a real user DB copy).
- [ ] Rollback plan: keep previous version downloadable; DB migrations are
      append-only so downgrades never lose data.

## 6. Support & docs

- [ ] Landing/docs site already exists (`docs/`, GitHub Pages) — add:
      data-format page (transparency = trust), CLI reference (agent users are
      a paying niche), migration guide from the Avalonia 0.6.x.
- [ ] In-app "Where is my data?" page pointing at `~/.taskly/tasks.db`.
- [ ] Support inbox + refund policy wired into the store checkout.
