#!/bin/bash
# Builds release artifacts separately from the running development app.
# SIGN_IDENTITY: Developer ID Application identity; NOTARY_PROFILE: notarytool Keychain profile.
# SKIP_BUILD=1 resumes packaging/notarization of an already verified release app.
set -euo pipefail
cd "$(dirname "$0")/.."
RELEASE_DIR="${RELEASE_DIR:-build/release}"
APP="$RELEASE_DIR/Vital.app"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
# Public artifacts must be reproducible from a committed source revision.
[ -n "${SIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ] || {
  echo "Set SIGN_IDENTITY to a Developer ID Application identity and NOTARY_PROFILE to a Keychain profile." >&2
  exit 1
}
[ -z "$(git status --porcelain)" ] || { echo "Commit source changes before building a release." >&2; exit 1; }
[ ! -f "$RELEASE_DIR/SHA256SUMS" ] || { echo "Release directory already contains completed artifacts. Choose a new version/directory." >&2; exit 1; }
export VERSION
mkdir -p "$RELEASE_DIR"

[ -f Resources/AppIcon.icns ] || {
  swift Scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
}
if [ "${SKIP_BUILD:-0}" != 1 ]; then
  if [ -n "${SIGN_IDENTITY:-}" ]; then
    HARDENED_RUNTIME=1 APP_OUTPUT="$APP" Scripts/build-app.sh release
  else
    APP_OUTPUT="$APP" Scripts/build-app.sh release
  fi
fi
codesign --verify --deep --strict "$APP"
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[ "$APP_VERSION" = "$VERSION" ] || { echo "App version does not match requested release." >&2; exit 1; }
APP_REVISION=$(/usr/libexec/PlistBuddy -c 'Print :VitalSourceRevision' "$APP/Contents/Info.plist")
[ "$APP_REVISION" = "$(git rev-parse HEAD)" ] || { echo "Release app was built from another source revision." >&2; exit 1; }

if [ -n "${NOTARY_PROFILE:-}" ]; then
  [ -n "${SIGN_IDENTITY:-}" ] || { echo "Notarization requires SIGN_IDENTITY." >&2; exit 1; }
  codesign -dv --verbose=4 "$APP" 2>&1 | /usr/bin/grep 'Authority=Developer ID Application:' >/dev/null || {
    echo "Notarization requires Developer ID Application signing." >&2; exit 1;
  }
  # Notarize and staple the app before packaging, so both download formats carry its ticket.
  ditto -c -k --keepParent "$APP" "$RELEASE_DIR/notarization.zip"
  xcrun notarytool submit "$RELEASE_DIR/notarization.zip" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$APP"
  xcrun stapler validate "$APP"
fi

STAGING="$(mktemp -d "$RELEASE_DIR/dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
DMG="$RELEASE_DIR/Vital.dmg"
hdiutil create -volname "Vital" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
if [ -n "${SIGN_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
if [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG"
  xcrun stapler validate "$DMG"
  spctl --assess --type execute --verbose=2 "$APP"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

ZIP="$RELEASE_DIR/Vital-$VERSION.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
SUM=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)
printf 'sha256: %s\n' "$SUM" > "$RELEASE_DIR/release-notes.txt"
(cd "$RELEASE_DIR" && shasum -a 256 "Vital-$VERSION.zip" Vital.dmg) > "$RELEASE_DIR/SHA256SUMS"
printf 'version: %s\nsource: %s\n' "$VERSION" "$APP_REVISION" > "$RELEASE_DIR/source.txt"
echo "Built $DMG"
echo "Built $ZIP"
echo "Updater checksum: $SUM"
if [ -z "${NOTARY_PROFILE:-}" ]; then echo "Notarization pending: set NOTARY_PROFILE and rerun with SKIP_BUILD=1."; fi
