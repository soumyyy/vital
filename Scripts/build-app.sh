#!/bin/bash
# Builds build/Vital.app. Usage: Scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Vital"
APP="build/Vital.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchDaemons"
cp "$BIN" "$APP/Contents/MacOS/Vital"
[ "$CONFIG" = release ] && strip -x "$APP/Contents/MacOS/Vital"   # drop local symbols: smaller file, same behaviour
cp "$(dirname "$BIN")/VitalFanHelper" "$APP/Contents/MacOS/VitalFanHelper"
cp Resources/dev.soumya.vital.fans.plist "$APP/Contents/Library/LaunchDaemons/"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP/Contents/MacOS/VitalFanHelper"
cp Resources/Info.plist "$APP/Contents/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign "${SIGN_IDENTITY:--}" "$APP"   # ad hoc unless SIGN_IDENTITY is set
echo "Built $APP"
