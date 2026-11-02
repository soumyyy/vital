# Release verification

## Automated checks

Run `swift test`, `swift build -c release`, and the metadata/script checks in `.github/workflows/ci.yml`. The workflow runs on Apple Silicon macOS 15 and 26. CI does not prove physical fan behavior or macOS approval dialogs.

Fan regression tests cover recovery after a new helper session, failure before the first hardware write, unreadable recovery state, interrupted transactions, and retry after Auto restoration fails. Hardware-free tests use fake fan controllers.

The release script requires a clean Git tree, Developer ID signing, and notarization. It records the source revision in the app and `source.txt`. It refuses to overwrite completed release artifacts.

## Physical and OS checks

Record results against the exact released version. Do not claim untested combinations as verified.

- Fresh installation from a downloaded DMG with Gatekeeper enabled.
- Spotlight launch, repeat launch without duplicates, Overview default, icon click to close, Escape, and outside click.
- Launch at login enabled, disabled, and denied by macOS.
- Personal-folder access granted, declined, and revoked. Check the unmeasured storage explanation.
- Upgrade from an older app through the public release feed, including restart and helper restoration.
- Read-only installation folder: no replacement or permission escalation, with manual-download guidance.
- Fan control approved, denied, and revoked. A declined permission must not become consent after an upgrade.
- Manual fan control followed by app crash, helper crash, and sleep/wake. Verify actual hardware mode returns to Auto.
- Quit and Force Quit confirmations. Verify system processes are protected and failed actions are reported.
- Another supported Mac, including a fanless Mac. Check missing sensor states.
- Light, dark, Reduce Transparency, small screens, and the macOS 14/15 material fallback.

Physical sleep and another Mac require access to those machines. Never trigger a sleep or stress test on the owner's active session without arranging it first.
