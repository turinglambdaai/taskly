# Taskly user guide

**English** · [简体中文](USER-GUIDE.zh-CN.md)

A local task manager for lists, quick capture and scheduled reminders.

## Availability

Development preview; no paid checkout is open. A future official desktop purchase will be announced with its delivered terms.

## Platforms and installation

Desktop previews for macOS, Windows and Linux. Select the OS and CPU shown on the release asset; mobile and watch applications are not delivered products.

Use [official Releases](https://github.com/turlamai/taskly/releases), select an explicitly listed OS/architecture asset, read its release notes and check supplied checksums. An absent asset/platform is not a delivery promise. Preview builds may lack publisher signing or notarization; do not disable system-wide security protections to install them.

## Your first successful session

1. Create a list and add one non-sensitive task. Check the parsed date before saving.
2. Complete the task, reopen the application and confirm the saved state.
3. For reminders, allow OS notifications and test one while the app is running. Do not assume delivery while it is closed or the computer sleeps.

## Data, backup and recovery

Tasks use SQLite, normally ~/.taskly/tasks.db, with configuration in ~/.taskly/config.ini. Quit every Taskly process, then back up the directory, including any WAL/SHM files. Restore into a separate copy first. A cloud-synced live database is not a supported concurrent-editing mechanism.

## Keyboard and editing

Use Command on macOS and Ctrl on Windows/Linux: 1–4 switches smart views, N focuses quick add, F focuses search, and Shift+C toggles completed tasks. In the task list, arrows move selection and Enter opens inline editing. The editor always shows Save and Cancel; Enter saves, while Escape or Cancel discards the whole draft, then a second Escape clears selection. The date action offers Today, Tomorrow and This Weekend above the native calendar. Choosing a date only changes the draft: Save, Enter or clicking another row persists it, with saving/success/error feedback. A failed explicit save keeps the draft available for retry. Delete is staged for about six seconds; Undo restores the same task identity and metadata.

## Network, keys and privacy

Core task use is local. Update checks/downloads and links you open contact external services. Sharing a database or diagnostics can disclose task titles and notes.

## Known limits

Reminders are evaluated consistently by the shared core on all three desktop hosts, but Taskly must be running and the OS must allow notification delivery. The standalone packaged CLI is not yet part of desktop releases; source CLI instructions remain in the README.

## Updates and removal

Back up data and read the destination release notes first. An in-app update check does not necessarily install an update for your channel; follow the manual for portable, installer and source paths. Never bypass a failed signature check or replace the program with an untrusted artifact. On failure, preserve data and the error, then recover with a trusted release. Removing the program does not necessarily erase its separate data directory; verify your backup before deleting personal data.

DMG, MSI, deb/rpm and portable archives replace application files, not `~/.taskly/`. If an update fails, quit all Taskly processes and reinstall the previous trusted build using the same installation shape; portable users can return to the previous program directory. The exact per-shape rollback table is in the update contract below.

## Get help

Report problems in [GitHub Issues](https://github.com/turlamai/taskly/issues), in English or Chinese. Include the version, OS/architecture, installation channel, steps, expected result and actual result. Reproduce with synthetic input first; do not attach keys, credentials, databases, private source documents or complete logs. Public support has no guaranteed response time.

## Further reading

- [Detailed manual](../docs/manual.html)
- [Data format](../shared/spec/DATA-FORMAT.md)
- [Update contract](../shared/spec/UPDATE.md)
- [Project overview and development](../README.md)
- [Current licence](../LICENSE)
