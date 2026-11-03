# Changelog

All notable changes. Versions follow the GitHub releases.

## 0.1.5 (2026-11-03)
- **24 hour history.** Vital keeps a day of CPU, memory, heat and network by the minute in a small file, for `vital history` and AI agents. The Overview still graphs the last 5 minutes.
- **Clearer app rows.** An app made of many processes says so ("Google Chrome  96 processes"), and the Quit sheet says how many will close.
- **Command line.** `vital status`, `vital apps` and `vital history` print text or JSON, read-only, for terminals and AI agents. See docs/CLI.md.
- **npm.** `npx vital-mac install` downloads the notarized release, verifies its checksum and installs it.
- Homebrew starts Vital after installing it.

## 0.1.4 (2026-11-03)
- Fan control keeps working after you replace the app (DMG drag, Homebrew, restore). The helper is now trusted by who signed it, not by one exact build, so a newer Vital can talk to an older helper. On launch Vital also restarts the helper if it is not the one bundled with the app, and **Reconnect** restarts a helper that has stopped answering.

## 0.1.3 (2026-11-03)
- New black and white app icon.
- Translucent red Quit pill on a vital's status line.
- Overview is the default page and fits its content; the four app lists keep a steady panel height.
- Details are grouped under titled sections.
- Update Software and a new About window.
- Fan control uses a separate helper identity so development builds cannot replace the installed helper.

## 0.1.2 (2026-11-02)
- First public release: signed and notarized DMG, optional login launch, manual update checks.
- Fan control records the original automatic mode before changing hardware and recovers it after a helper restart.
- Updates verify the developer signature and replace the app atomically with a backup.
