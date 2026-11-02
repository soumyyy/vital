# Changelog

All notable changes. Versions follow the GitHub releases.

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
