# Release and update Vital

This runbook describes publishing outside the Mac App Store, including future Homebrew Cask delivery.

## Use the public update feed

The owner selected the public `soumyyy/vital` repository for source and releases. `UpdateFeed.defaultURL` targets `https://api.github.com/repos/soumyyy/vital/releases/latest`. Keep that endpoint reachable without credentials.

Never put a GitHub token in the app. Keep versioned downloads immutable.

## Build a candidate

Run `swift test`, then select a version greater than the last public release and a higher build number. The updater compares the short version; increasing only the build number does not offer an update.

Example for the release after local candidate 0.1.1 (3):

```sh
VERSION=0.1.2 BUILD=4 \
RELEASE_DIR=build/releases/0.1.2 \
SIGN_IDENTITY="Developer ID Application: Soumya Maheshwari (4W769MPDJ6)" \
NOTARY_PROFILE=vital-notary \
Scripts/release.sh
```

Commit all release changes first. The script rejects an uncommitted tree and refuses to overwrite completed artifacts.

The script signs the helper and app inside out with hardened runtime and secure timestamps. It notarizes and staples the app, then builds, signs, notarizes, and staples the DMG. It verifies Gatekeeper acceptance and writes:

- `Vital.app`
- `Vital.dmg` for manual installation and Homebrew
- `Vital-<version>.zip` for the in-app updater
- `SHA256SUMS`
- `release-notes.txt`, containing the updater ZIP checksum line

`RELEASE_DIR` keeps distribution work separate from `/Applications/Vital.app` and `build/Vital.app`. Without an override, it defaults to `build/release/`. `SKIP_BUILD=1` resumes packaging/notarization of an existing signed app; use the same version, directory, and signing identity. Do not use it to pick up source changes.

If the Keychain profile is missing, configure `notarytool store-credentials vital-notary` using Apple-supported credentials. Enter passwords only in a secure prompt or private credential card. A `notarytool` profile is local machine setup, not a repository file.

## Verify the candidate

Substitute the actual version directory:

```sh
codesign --verify --deep --strict build/releases/0.1.2/Vital.app
xcrun stapler validate build/releases/0.1.2/Vital.app
xcrun stapler validate build/releases/0.1.2/Vital.dmg
spctl --assess --type execute --verbose=2 build/releases/0.1.2/Vital.app
spctl --assess --type open --context context:primary-signature --verbose=2 build/releases/0.1.2/Vital.dmg
(cd build/releases/0.1.2 && shasum -a 256 -c SHA256SUMS)
```

Gatekeeper must report acceptance with `Notarized Developer ID`. Check an extracted copy of the updater ZIP for a valid signature and stapled ticket as well.

On a clean test account or another Mac, test installation, real update/restart, fan approval denied then granted, helper recovery after an update, and uninstall. Test read-only installation handling. Verify fan safety under sleep/wake and process interruption before broad release.

For local replacement of a registered development app, quit it and unregister its helper before replacing the bundle. Use one registered copy per bundle identifier. Removing stale Launch Services records for deleted builds may be needed after earlier development copies confused resolution. Do not reset all system registrations or weaken signing checks.

## Publish the version

1. Verify the version, build, feed URL, and artifact checksums one final time.
2. Create a GitHub release in the chosen public repository with a tag matching the version, such as `v0.1.2`.
3. Attach both `Vital-0.1.2.zip` and `Vital.dmg`. Use the checksum line from the final `release-notes.txt` in the release body, alongside human-readable changes.
4. Publish as a normal release when ready. The updater skips drafts and prereleases.
5. Check the unauthenticated latest-release endpoint and use Update Software from an older installed copy. Confirm the correct version is offered, installed, and restarted, and that any required fan approval is visible.

Running the release script does not publish files or change GitHub visibility. Published artifacts must not be silently replaced under the same version/tag.

## Homebrew

The cask lives in this repository (`Casks/vital.rb`), so the repository is its own tap. Users add it by URL, because the repository is not named `homebrew-*`:

```sh
brew tap soumyyy/vital https://github.com/soumyyy/vital
brew install --cask soumyyy/vital/vital
```

After publishing a release:

```sh
Scripts/update-cask.sh 0.1.4        # reads the DMG checksum from the release's SHA256SUMS
brew audit --cask --online soumyyy/vital/vital
git add Casks/vital.rb && git commit -m "Cask: 0.1.4" && git push
```

The cask checksum is for `Vital.dmg`; the updater uses the ZIP checksum, which is different. Uninstalling runs `Vital --unregister-fan-helper`, so removal also drops the optional fan-control helper. Installation never grants fan-control approval; that stays in the app. Official Homebrew Cask submission can come later and is subject to Homebrew's acceptance rules.
