#!/bin/bash
# Builds build/Vital.app. Usage: Scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
# Fan control needs the app and its helper signed by the same identity: macOS pins the helper to the app's
# signature and drops the approval when it changes. Use the local Apple Development identity unless told otherwise;
# fall back to ad hoc (everything but fan control works).
if [ -z "${SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*\([0-9A-F]\{40\}\) "Apple Development.*/\1/p' | head -1)"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SIGN_FLAGS=(--force --sign "$SIGN_IDENTITY")
if [ "${HARDENED_RUNTIME:-0}" = 1 ]; then
  [ "$SIGN_IDENTITY" != "-" ] || { echo "Hardened release builds require a signing identity." >&2; exit 1; }
  SIGN_FLAGS+=(--options runtime --timestamp)
fi
[ "$SIGN_IDENTITY" = "-" ] && echo "warning: ad hoc signing; fan control will not connect" >&2
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Vital"
APP="${APP_OUTPUT:-build/Vital.app}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"
cp "$BIN" "$APP/Contents/MacOS/Vital"
[ "$CONFIG" = release ] && strip -x "$APP/Contents/MacOS/Vital"   # drop local symbols: smaller file, same behaviour
cp "$(dirname "$BIN")/VitalFanHelper" "$APP/Contents/MacOS/VitalFanHelper"
cp Resources/dev.soumya.vital.fans.plist "$APP/Contents/Library/LaunchDaemons/"
codesign "${SIGN_FLAGS[@]}" "$APP/Contents/MacOS/VitalFanHelper"
# Record the helper build in the daemon configuration to distinguish local rebuilds.
HELPER_HASH=$(codesign -dv --verbose=4 "$APP/Contents/MacOS/VitalFanHelper" 2>&1 | sed -n 's/^CDHash=//p')
[ -n "$HELPER_HASH" ]
/usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables dict' "$APP/Contents/Library/LaunchDaemons/dev.soumya.vital.fans.plist"
/usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:VITAL_FAN_HELPER_BUILD string $HELPER_HASH" "$APP/Contents/Library/LaunchDaemons/dev.soumya.vital.fans.plist"

cp Resources/Info.plist "$APP/Contents/Info.plist"
SOURCE_REVISION=$(git rev-parse HEAD)
/usr/libexec/PlistBuddy -c "Add :VitalSourceRevision string $SOURCE_REVISION" "$APP/Contents/Info.plist"
# VERSION and BUILD override the numbers in Info.plist (releases, update tests).
[ -n "${VERSION:-}" ] && /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
[ -n "${BUILD:-}" ] && /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign "${SIGN_FLAGS[@]}" "$APP"   # ad hoc unless SIGN_IDENTITY is set
echo "Built $APP"
