#!/bin/bash
# Builds a distributable EasySpeech DMG.
#
# Without an Apple Developer ID ($99/yr) the app can only be ad-hoc signed, so macOS
# quarantines it on download. See "Installing" in the README for what users must do.
# With a Developer ID, set CODESIGN_IDENTITY and this produces a clean, notarizable DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/EasySpeech.app"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ARCH="$(uname -m)"
DMG="$ROOT/build/EasySpeech-${VERSION}-macOS-${ARCH}.dmg"

echo "==> Building app"
"$ROOT/build.sh" >/dev/null

echo "==> Staging"
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating DMG"
rm -f "$DMG"
hdiutil create \
  -volname "EasySpeech $VERSION" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  -quiet \
  "$DMG"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  echo "==> Signing DMG as $CODESIGN_IDENTITY"
  codesign --force --sign "$CODESIGN_IDENTITY" "$DMG"
fi

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo ""
echo "Built $DMG ($SIZE)"
shasum -a 256 "$DMG" | awk '{print "sha256: " $1}'
