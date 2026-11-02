# Vital: current state

Last verified: 2026-11-03. Read this first when resuming work, then follow [the release runbook](RELEASING.md). Earlier rounds in [tasks/todo.md](../tasks/todo.md) are history, not the current release checklist.

## Where we left off

Fan control works on the owner's M3 MacBook Pro. The maximum target of 6,800 RPM was applied and actual speed reached roughly 6,800–6,900 RPM. A later 4,000 RPM check reached 3,966 RPM and verified Auto restoration. Keep manual control opt-in; normal launch must never run a fan test.

A Developer ID Application certificate was created through Xcode and is available with its private key in the local keychain:

- Identity: `Developer ID Application: Soumya Maheshwari (4W769MPDJ6)`
- Team ID: `4W769MPDJ6`
- Notarization Keychain profile: `vital-notary`

Credentials are in Keychain, not the repository. Do not ask for passwords in chat or commit credentials, private keys, or certificate exports.

## Installed app and release artifacts

- The running app is `/Applications/Vital.app`, version **0.1.0**, build **2**. Use this installed copy for normal launches; do not start a second development copy with the same bundle identifier.
- **0.1.0 (2)** is signed, notarized, and stapled under `build/release/`.
- **0.1.1 (3)** includes update/permission recovery fixes and is signed, notarized, and stapled under `build/releases/0.1.1/`. It has not replaced the installed app and has not been published by this work.
- Apple accepted both the app and DMG submissions for each candidate; Gatekeeper reported `Notarized Developer ID`.
- Latest full test run: **142 tests passed**. This is not proof of a clean-machine upgrade or every macOS approval path.
- Source version defaults are now 0.1.2 (4). Earlier artifacts remain separate and must not be overwritten.

The 0.1.1 ZIP is `build/releases/0.1.1/Vital-0.1.1.zip`; its SHA-256 is:

```text
8faacedfac2b44b52bf49db62c5cd926ee03a1aae6ea63f45927e237d7aaff35
```

The DMG is `build/releases/0.1.1/Vital.dmg`; its SHA-256 is:

```text
3c24fede020de847a692e589ad327a457aef23ca10ef0b758d98f0655ce34489
```

Both checksums are also in that directory's `SHA256SUMS`. `build/` is ignored by Git: artifacts may disappear after cleanup or on another machine. Do not rebuild over a published version with different bytes.

## Public release preparation

The owner authorized making `soumyyy/vital` public, including its source history. The history and current source passed a Gitleaks scan. GitHub visibility is now public. The updater already targets this repository; it returns 404 until the first normal release is published.

The next candidate is **0.1.2 (4)**. It includes both sessions' UI, installation, signing, and updater changes, plus persistent fan recovery and helper restart after failure. The root helper stores only its owned fans' original automatic modes under `/var/db/dev.soumya.vital`. It records them before writing manual mode, restores them on restart, and clears the record only after verified Auto restoration. If recovery storage cannot be read or written, manual control fails closed.

The release script now requires committed source and notarization. CI tests and builds on macOS 15 and 26. See [installation](INSTALL.md) and [release verification](TESTING.md).

## Update and permission behavior

- Users explicitly select Update Software, review the release, then choose Update and Restart. No background update check is scheduled.
- The updater consumes `Vital*.zip` assets from a published, non-prerelease GitHub release. It checks supplied SHA-256, version, bundle identifier, nested signatures, and a matching-team Apple-issued Developer ID signature. Unsigned/ad-hoc copies cannot bootstrap trust using a feed checksum alone.
- Update preparation unregisters the old fan helper before bundle replacement. Failure to unregister aborts installation. Only previously enabled fan control is eligible for restoration; declined permission is not converted into consent.
- Recovery intent persists across restart. Registration failures keep the marker for retry and show an error. If macOS requires approval again, Heat provides Approve control and opens System Settings when chosen.
- Replacement creates a backup, then atomically exchanges the old and new paths. A failed exchange leaves the installed app in place; there is no gap where the normal app path is absent.
- Read-only install locations show a manual-download explanation. The custom updater does not elevate itself with an administrator password to replace protected files.
- Personal-folder access is requested only when Scan is selected. Launch at login is opt-in and reports setup failures. Developer signing/notarization credentials are never required from end users.

Relevant code: `Updater.swift`, `FanClient.swift`, `About.swift`, `HelperUpdateRecovery.swift`, `UpdateBundleSwap.swift`, and their tests. See [fan helper details](superpowers/specs/2026-11-02-fan-control-helper.md).

## Remaining verification

- Run a clean-machine install and real GitHub upgrade with the final public feed.
- Exercise approval granted, declined, revoked, and requested again after an update; test a read-only install folder.
- Verify manual fan control returns to Auto across real sleep/wake, app crash, and helper restart. Unit tests cover the state transitions; not every OS path has been exercised live.
- Test another supported Apple Silicon Mac and macOS 14/15 fallback before broad compatibility claims.
- Complete Homebrew installation, upgrade, helper removal, and cask audit checks after publishing the tap.

There are existing uncommitted changes across UI, packaging, updater code, tests, and notes. Inspect `git status` and preserve work from other sessions. The final commit, release publication, and end-to-end results are recorded after verification.
