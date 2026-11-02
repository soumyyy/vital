#!/bin/bash
# Points Casks/vital.rb at a published release. Usage: Scripts/update-cask.sh 0.1.4
# Reads the DMG checksum from the release's SHA256SUMS asset, so run it after `gh release create`.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:?usage: Scripts/update-cask.sh <version>}"
SUM=$(gh release download "v$VERSION" --pattern SHA256SUMS --output - | awk '$2 == "Vital.dmg" { print $1 }')
[ "${#SUM}" -eq 64 ] || { echo "No Vital.dmg checksum found in release v$VERSION." >&2; exit 1; }
sed -i '' -e "s/^  version \".*\"/  version \"$VERSION\"/" -e "s/^  sha256 \".*\"/  sha256 \"$SUM\"/" Casks/vital.rb
echo "Casks/vital.rb now points at v$VERSION ($SUM)."
echo "Next: brew audit --cask --online soumyyy/vital/vital, then commit."
