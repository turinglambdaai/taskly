# Taskly Update Contract

> Online updates are the release vehicle: every platform must be able to
> check, download, verify and install a new version without the user
> hunting for download pages. The **behavior** (triggers, UX, strings,
> failure handling) is identical on all platforms; the **transport and
> install mechanism** is native to each platform, like every other part
> of the Taskly architecture.

## Behavior contract (all platforms)

- **Triggers**: one silent check shortly after launch (throttled: at most
  once per 4 hours, persisted as config key `last-update-check`, unix
  epoch seconds, host-owned via `get_setting`/`set_setting`), plus a
  manual `检查更新… / Check for Updates…` menu item (family menu
  convention: Help menu on Windows/Linux, App menu below About on macOS)
  that bypasses the throttle.
- **Silent mode**: network failure / rate limit → silently ignore (never
  nag). Manual mode reports every outcome.
- **Newer version found** (semver compare, downgrades ignored) → dialog
  with the new version: `立即更新 / Update` (download + install) or
  `取消 / Cancel`. Up-to-date → `当前已是最新版本 / Up to date`.
- **Download**: performed by the backend over the `check_updates` /
  `start_download` / `update_state` RPCs (rivet/distribution family
  pattern — Ed25519 manifest verify and sha256 artifact verify live in
  the backend; hosts never implement crypto). Hosts poll `update_state`
  (phase: idle | checking | downloading | downloaded | error) and show
  progress. For schema compatibility, `start_download` is a start/cancel
  toggle while a transfer is active: a second call interrupts the worker,
  removes partial data, returns to `idle`, and preserves the candidate
  so the user can retry.
- **Download must be bounded and cancellable**: a stalled transfer
  surfaces a retryable error after a finite timeout, and the progress UI
  offers Cancel — cancelling stops the transfer and returns to the
  offer without restarting the app (issue #13).
- **Install failure** → non-crashing error with the platform message;
  the running version keeps working (same rule as notifications).
- **CLI parity**: `--json` output and exit codes are version-stable; an
  update must never change golden outputs within a major version.
- i18n keys are shared (`shared/i18n`): `updateCheckNow`, `updateChecking`,
  `updateUpToDate`, `updateAvailableTitle`, `updateAvailableBody`,
  `updateRestart`, `updateCheckFailed`, `updateDownloading`,
  `updateDownloadPercent`, `updateDownloaded`, `updateQuitAndInstall`,
  `updateInstallHint`, `updateOpenFolder`, `updateInstallFailed`,
  `updatePortable`, `updateNotInstalled`, `updateOpenReleases`,
  `updateReadyBody`.

## Platform mechanisms

The release pipeline signs and uploads `update-manifest.json` (the
self-contained signed wrapper, below) for every release, so the feed
exists on all platforms from day one.

| Platform | Feed | Install | Integrity | Status |
|---|---|---|---|---|
| macOS Apple silicon | feed `macos`/`arm64` zip entry | zip → sha256 → ditto → atomic swap in place (`.old` copy kept until relaunch); the DMG is the human installer, not a feed artifact | Ed25519 wrapper signature (CryptoKit, `UpdateService.swift`) + artifact sha256 | wired since 1.1.1 |
| macOS Intel | feed `macos`/`x64` zip entry | same swap flow on the x64 build (hosts match their compile-time architecture) | same | wired since 1.3.0 |
| Windows x64 | signed `windows`/`x64` zip + MSI entries | portable zip → handoff `update-install.cmd`: wait for app exit → `tar -xf` extract → swap install dir in place → relaunch; failure marker (`update-failed.txt`) reported on next launch. MSI installs (host declares `install-flavor=msi` at startup): backend selects the signed MSI artifact directly, then handoff `msi-install.cmd`: wait for app exit → `msiexec /passive /norestart /i` (per-machine installs surface one UAC consent; msiexec log at `%TEMP%\taskly-update\msiexec.log`) → relaunch; failure marker on next launch | Ed25519 wrapper signature + signed size/SHA-256 for both zip and MSI | portable wired since 1.2.0; MSI online upgrade since 0.1.2 (signed-artifact hardening in 0.2.x) |
| Windows ARM64 | — | no native package exists (Racket ships no Windows-on-ARM runtime); run the x64 build under Windows on ARM's built-in x64 emulation | — | documented since 1.3.0 |
| Linux x64 | signed tar.gz + AppImage entries | three install shapes (host declares `install-flavor` at startup): **AppImage** (`APPIMAGE` env set) — backend selects the signed AppImage artifact directly, stages beside the running image, verifies signed size/SHA-256, and atomically renames it over `$APPIMAGE` with exec bits set; host asks for consent, then `execl`s the replaced image. **deb/rpm** (exe under /opt/taskly or /usr) — download kept, dialog points at the system package manager (`updateUsePackageManager`); no self-swap of a system-managed prefix. **tarball** — download + "open folder" manual extract, unchanged | Ed25519 wrapper signature + signed size/SHA-256 for tar.gz and AppImage | tarball wired since 1.2.0; AppImage in-place since 0.1.2 (signed-artifact hardening in 0.2.x); deb/rpm guidance since 0.1.2 |

(The frozen v1 line used Velopack on Windows and a tarball replacer on
Linux; those mechanisms died with that line — the Rivet hosts start from
the manifest feed above.)

## `update-manifest.json`

Generated by `scripts/make-update-manifest.sh` from the release
artifacts and uploaded as a single release asset. It is the family
signed-wrapper format (`rivet/distribution`): the inner manifest travels
base64-encoded inside a JSON envelope, so the Ed25519 signature covers
the exact bytes every client verifies.

```json
{
  "schema": 1,
  "payload": "<base64 of the inner manifest JSON>",
  "signature": { "algorithm": "ed25519", "key_id": "taskly-2026-10",
                 "value": "<base64, 64 bytes>" }
}
```

Inner manifest (decoded `payload`) — rivet's manifest schema:

```json
{
  "schema": 1,
  "application_id": "app.taskly.Taskly",
  "version": "1.2.0",
  "build": 1,
  "channel": "stable",
  "published_at": "2026-10-09T12:00:00Z",
  "minimum_version": "0.0.0",
  "previous_version": null,
  "rollback_allowed": true,
  "rollout": 100,
  "artifacts": [
    { "platform": "macos", "architecture": "arm64",
      "url": "https://…/taskly-1.3.0-macos-arm64.zip",
      "sha256": "<hex>", "size": 12345678, "installer": "zip", "arguments": [] },
    { "platform": "macos", "architecture": "x64", "…": "…" },
    { "platform": "windows", "architecture": "x64", "installer": "zip", "…": "…" },
    { "platform": "windows", "architecture": "x64", "installer": "msi", "…": "…" },
    { "platform": "linux", "architecture": "x64", "installer": "targz", "…": "…" },
    { "platform": "linux", "architecture": "x64", "installer": "appimage", "…": "…" }
  ]
}
```

- `version` must equal the root `VERSION` file (release preflight checks
  it, along with `rivet.rktd` and the updater module's embedded identity).
- Clients fetch
  `https://github.com/turinglambdaai/taskly/releases/latest/download/update-manifest.json`
  (the moving "latest" location; redirect-following is mandatory —
  release assets 302 to the CDN, rivet#153). Artifact URLs inside the
  manifest are pinned to the concrete tag.
- A sticky per-install rollout bucket (config key `rollout-bucket`,
  integer 0–99) gates staged rollouts against the manifest's `rollout`
  percentage.

## Release evidence (acceptance kind `release`)

The update chain carries its own acceptance requirement in
`rivet-acceptance.rktd` (`release-update` suite,
`racket/tests/release-update-test.rkt`), and the release pipeline's
publish job runs the suite on the exact tree being published — a release
cannot ship without its update evidence. The suite proves, at the
backend boundary every host shares:

- a plain-http feed can never yield a candidate (the HTTPS-only fetch
  gate fails closed), and a signed manifest whose artifact URLs are not
  HTTPS is refused at sign/parse time;
- a feed signed by another key, or under another key-id, fails
  verification (the embedded production key is the only trust anchor);
- semver refuses downgrades and `rollout: 0` gates the offer for every
  bucket;
- the N→N+1 lifecycle downloads through the real worker, verifies the
  artifact SHA-256 against the signed manifest, renames the `.partial`
  into place, and leaves `~/.taskly/tasks.db` byte-identical with the
  seeded task intact (data preservation);
- a sha-mismatched artifact never reaches the destination and permits
  retry;
- the Linux AppImage in-place swap replaces the running image
  (exec bits kept) with the database untouched — the one install arm the
  backend owns end to end. The host-side arms (macOS zip swap, Windows
  cmd/MSI handoff) are exercised on every release by the platform build
  and packaged-acceptance jobs; rollback and manual-recovery notes per
  install shape live in the lifecycle section of this document.

## Ed25519 signature

- Key type: Ed25519. Private key lives ONLY in the GitHub secret
  `UPDATE_ED25519_PRIVATE_KEY` (PEM) and in the release manager's local
  backup — never in the repository.
- Generate / inspect: `scripts/update-keys.sh` (openssl, one-time).
- Sign: inside `make-update-manifest.sh`, the PEM is converted to DER
  (`openssl pkey -outform DER`) and the wrapper is signed by
  `rivet/distribution`'s `write-signed-manifest` (which also validates
  the manifest against the schema before signing).
- Public key: embedded twice, same keypair — raw 32 bytes base64 in the
  macOS host (`UpdateService.publicKeyBase64`) and SPKI DER base64 in
  the backend updater (`racket/taskly/updater.rkt`). `key_id` is
  `taskly-2026-10`; clients pin it. Rotate = ship a build that trusts
  the next key before releases stop being signed with the old one.
- Verification: wrapper → schema 1 → key id → Ed25519 over the exact
  payload bytes; then size + sha256 of the downloaded artifact against
  the signed manifest. Any mismatch aborts the update silently in
  silent mode, with an error in manual mode.

## Rollout rules

- Downgrades are never auto-installed; semver compare is numeric per
  segment.
- The updater must never delete or touch `~/.taskly/` (DB + config) —
  it swaps application bundles/prefixes only.
- A failed swap must leave the previous install runnable (macOS keeps a
  `.old` copy until the next successful launch; Windows restores the
  renamed directory and writes a failure marker the next launch
  reports).
- Update failure text must leave the screen with the user: the error is
  selectable in the macOS sheet and the Linux dialog, and the Windows
  dialogs carry a "copy error" button (`updateCopyError`) that puts the
  failure message on the clipboard. A bug report starts from this string.
