#!/bin/bash
# Builds a signed, notarized Vital.dmg.
#   SIGN_IDENTITY   "Developer ID Application: Your Name (TEAMID)"  (security find-identity -v -p codesigning)
#   NOTARY_PROFILE  keychain profile made with: xcrun notarytool store-credentials <name>
# Without SIGN_IDENTITY the app is ad-hoc signed and the DMG is not notarized (fine for personal use).
set -euo pipefail
cd "$(dirname "$0")/.."

[ -f Resources/AppIcon.icns ] || {
  swift Scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
}

if [ -n "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY="$SIGN_IDENTITY" Scripts/build-app.sh release
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" build/Vital.app
else
  Scripts/build-app.sh release
fi

rm -rf build/dmg build/Vital.dmg
mkdir -p build/dmg
cp -R build/Vital.app build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "Vital" -srcfolder build/dmg -ov -format UDZO build/Vital.dmg >/dev/null

if [ -n "${SIGN_IDENTITY:-}" ] && [ -n "${NOTARY_PROFILE:-}" ]; then
  xcrun notarytool submit build/Vital.dmg --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple build/Vital.dmg
fi
echo "Built build/Vital.dmg"

# The in-app updater downloads this zip. Its checksum goes in the release notes as a line "sha256: <hex>".
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
rm -f "build/Vital-$VERSION.zip"
ditto -c -k --keepParent build/Vital.app "build/Vital-$VERSION.zip"
SUM=$(shasum -a 256 "build/Vital-$VERSION.zip" | cut -d' ' -f1)
echo "Built build/Vital-$VERSION.zip"
echo "sha256: $SUM"
echo
echo "Publish:  gh release create v$VERSION build/Vital-$VERSION.zip build/Vital.dmg --title \"Vital $VERSION\" --notes \"What changed.\n\nsha256: $SUM\""
