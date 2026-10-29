# Taskly installation, first-run and visual audit — 2026-10

This audit treats Taskly as a Rivet reference application. A source build,
archive creation or green unrelated check is not evidence that a person can
install, understand and remove the product.

## Evidence baseline

| Area | Evidence reviewed | Result before this change |
|---|---|---|
| Windows package | Published v0.2.6 MSI digest, Authenticode status, installed-file signature, uninstall registry entry and Start-menu shortcut on Windows | MSI and executable were `NotSigned`; registration and shortcut existed. SmartScreen reputation was not exercised. |
| macOS package | Release workflow, Rivet distribution contract and DMG assets | DMG shape and ad-hoc development signing existed. Developer ID signing, notarization, stapling and a real Gatekeeper install were not verified. |
| Linux package | Published v0.2.6 deb metadata and extracted file tree | deb installed `/opt/taskly/RivetHost`, desktop entry and icon, depending on GTK 4. rpm install, AppImage desktop integration and upgrade behavior were not exercised. |
| Packaged acceptance | `scripts/acceptance/package.rkt` and native UI suites | Package acceptance ran `package --skip-launch-smoke` and then unconditionally wrote `package-verified: true`. Native UI launched a staged/archive executable, not an installer-installed application. |
| First run | Shared strings and three native empty-state implementations | A connected empty database only said “No tasks”; the manual unnecessarily told people to create a list even though Taskly creates a default list. |
| Task-date golden path | PR #78 implementation and packaged UI suites | Save/Cancel and date semantics were being repaired, but the installation-to-cold-restart journey was not one mandatory evidence chain. |
| Visual system | Shared design contract, Windows XAML, macOS SwiftUI and GTK palettes, committed screenshots | Windows used Taskly's warm palette while macOS/Linux still implemented a system-blue Reminders palette. Several secondary/tertiary colors missed useful 4.5:1 text or 3:1 boundary contrast. |
| Accessibility | UIA, AX and AT-SPI drivers | The three native semantics were exercised, but installation lifecycle and first-run guidance were not acceptance requirements. |

No current macOS or Linux desktop was available during this local audit. Native
screenshots, Gatekeeper behavior, HiDPI composition and screen-reader output on
those systems remain unverified until the acceptance jobs produce fresh
artifacts. The Windows computer-control surface was also unavailable, so code
or historical screenshots are not reported as current visual runtime proof.

## Defects and disposition

### P0 — false installation evidence

The old suite could report a verified package without installing it. The new
package suite creates development release installers and dispatches to a native
installer preparation script. Native UI then launches that installed/copy-tested
application and must emit install-lifecycle evidence after removal.

- Windows: silently install MSI to its normal Program Files destination;
  resolve the executable from the Start-menu shortcut; require Apps & Features
  registration; record publisher trust; uninstall and require application/
  shortcut removal while synthetic data remains.
- macOS: mount DMG, require the Applications link, copy the application to an
  isolated install root, verify its code-signature structure, record Gatekeeper
  assessment without treating a development rejection as success, then remove
  the copied application while synthetic data remains.
- Linux: inspect deb/rpm, extract and validate AppImage structure, install deb,
  require executable/desktop entry/icon and valid desktop metadata, then remove
  the deb while synthetic data remains.

### P0 — incomplete golden path

Packaged acceptance now requires native evidence for first task creation, date
selection through the real editor, explicit Save acknowledgement and a cold
application restart that reads the persisted title/date. Windows uses UIA,
macOS uses AX, and Linux uses AT-SPI under a headless Wayland compositor. Linux
also runs a dedicated empty-profile pass before its existing 64-bit identity
and batch-operation regression. That pass exposed and fixed a real GTK4 defect:
the inline editor used an unmanaged popover on a plain button, so task-snapshot
row rebuilds destroyed its anchor and quick dates disappeared from both the
screen and AT-SPI tree. A native `GtkMenuButton` now owns that lifecycle.

### P1 — dead-end first run

The default list remains automatic. The empty state now points at quick add and
offers one harmless example in English and Chinese. No wizard, account or list
setup is required for the local-first core journey.

### P1 — three visual identities

Taskly now owns a shared warm terracotta action accent rather than cloning the
blue identity of a reference product. Platform-native type, controls, windows
and popovers remain native. Shared neutral tokens meet these automated floors:

- normal text and action accent: at least 4.5:1 against the theme background;
- meaningful input boundary: at least 3:1 against the theme background;
- token values must be present in the WinUI, SwiftUI and GTK implementations.

Smart-view category colors remain semantic and are not forced to terracotta.
The goal is common product identity with native platform behavior, not a custom
cross-platform widget language.

Fresh Windows packaged evidence also exposed a window-placement defect: the
preferred 1024×768 size was applied literally on a 1024×768 desktop, without
subtracting the taskbar or compensating for Windows' initial placement. The
right-hand header actions could therefore open outside the usable desktop.
Windows now clamps the preferred logical size to the current monitor work area,
centers it, and the installed-app UIA journey rejects any initial window whose
edges are not fully usable.

### P1 — obsolete Rivet baseline

Taskly previously pinned `9d766b4acab672844093204cb4845ef4ef933d2c`.
This change pins `82e4b75b738269b90ef490ebc6c11d30731b8d86`, the exact
upstream PR #361 revision that preserves the earlier real MSI-installed
UIA/uninstall and Linux desktop-identity work and fixes the branded DMG detach
race reproduced by Taskly's macOS x64 acceptance. The candidate is verified by
Taskly's own matrix; upstream PR checks and production credential gates are
reported separately and are not inferred from the pin.

## Release gates still open

These are deliberately not labelled complete:

1. acquire and protect production Windows and Apple signing identities;
2. Authenticode-sign and RFC3161-timestamp MSI/executable, then observe clean
   SmartScreen behavior on a fresh machine;
3. Developer ID sign, notarize and staple the macOS application/DMG, then pass
   Gatekeeper on fresh arm64 and x64 machines;
4. run rpm installation/removal on a Fedora-family runner and AppImage launch/
   desktop integration on representative Linux desktops;
5. test same-channel upgrade and downgrade rejection with real N→N+1 packages;
6. inspect fresh light/dark, 100%/150%/200% screenshots and screen-reader output
   from all three packaged hosts.

Production release remains blocked until those items have evidence. Preview
documentation names the unsigned/ad-hoc trust state and tells users not to
disable system security controls.

## Reusable Rivet reference contract

Future Rivet applications can copy the acceptance structure, not Taskly's
brand: installer creation → native installation/copy → packaged UI golden path
→ cold restart persistence → uninstall/application removal → synthetic data
preservation. They can also reuse semantic token names and contrast checks while
substituting their own approved brand palette. The package-install helper also
distinguishes bounded catalog retry from product execution, so network checksum
or timeout failures remain visible without being mislabeled as UI failures.
