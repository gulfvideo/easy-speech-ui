#!/bin/bash
# Builds a distributable EasySpeech DMG with a laid-out install window.
#
# Without an Apple Developer ID ($99/yr) the app can only be ad-hoc signed, so macOS
# quarantines it on download. See "Install" in the README for what users must do.
# With a Developer ID, set CODESIGN_IDENTITY and this produces a notarizable DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/EasySpeech.app"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")"
ARCH="$(uname -m)"
VOLUME="EasySpeech $VERSION"
DMG="$ROOT/build/EasySpeech-${VERSION}-macOS-${ARCH}.dmg"

# Finder records the backing image's path inside the volume's .DS_Store when it writes
# the background alias, and that file ships to everyone who downloads the DMG. Building
# the scratch image under a temp directory keeps the maintainer's home directory and
# project layout out of the published artifact.
SCRATCH_DIR="$(mktemp -d)"
SCRATCH="$SCRATCH_DIR/scratch.dmg"

echo "==> Building app"
"$ROOT/build.sh" >/dev/null

echo "==> Drawing background"
BACKGROUND="$ROOT/build/dmg-background.tiff"
swift "$ROOT/Packaging/MakeDMGBackground.swift" "$BACKGROUND" >/dev/null

echo "==> Staging"
STAGE="$(mktemp -d)"
cleanup() { rm -rf "$STAGE" "$SCRATCH_DIR"; }
trap cleanup EXIT
mkdir -p "$STAGE/.background"
cp "$BACKGROUND" "$STAGE/.background/background.tiff"
ditto "$APP" "$STAGE/EasySpeech.app"
ln -s /Applications "$STAGE/Applications"

echo "==> Creating writable image"
rm -f "$DMG" "$SCRATCH"
hdiutil create -volname "$VOLUME" -srcfolder "$STAGE" \
  -fs HFS+ -format UDRW -ov -quiet "$SCRATCH"

MOUNT_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$SCRATCH")"
MOUNT_POINT="$(echo "$MOUNT_OUTPUT" | grep -o '/Volumes/.*$' | head -1)"
[ -n "$MOUNT_POINT" ] || { echo "Could not mount the scratch image."; exit 1; }
detach() { hdiutil detach "$MOUNT_POINT" -quiet 2>/dev/null || true; cleanup; }
trap detach EXIT

echo "==> Arranging the window"
# Finder is the only thing that can write these view settings into .DS_Store.
if ! osascript <<APPLESCRIPT
tell application "Finder"
  tell disk "$VOLUME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    -- Height allows for the title bar so the 640x400 art isn't cropped.
    set the bounds of container window to {240, 140, 880, 588}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 12
    set background picture of viewOptions to file ".background:background.tiff"
    set position of item "EasySpeech.app" of container window to {165, 215}
    set position of item "Applications" of container window to {475, 215}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
APPLESCRIPT
then
  echo "    Finder wouldn't cooperate — shipping an unstyled image instead."
  echo "    (Grant Terminal automation access to Finder and re-run for the laid-out version.)"
fi

# Volume housekeeping macOS creates on a read-write mount; no reason to ship it.
rm -rf "$MOUNT_POINT/.fseventsd" "$MOUNT_POINT/.Trashes" "$MOUNT_POINT/.TemporaryItems" 2>/dev/null || true

sync

echo "==> Compressing"
hdiutil detach "$MOUNT_POINT" -quiet
trap cleanup EXIT
hdiutil convert "$SCRATCH" -format UDZO -imagekey zlib-level=9 -o "$DMG" -quiet
rm -rf "$SCRATCH_DIR"

# Fail loudly rather than publish an image carrying the maintainer's paths.
if hdiutil attach -nobrowse -readonly -quiet -mountpoint "$STAGE/verify" "$DMG" 2>/dev/null; then
  LEAKS="$(strings -a "$STAGE/verify/.DS_Store" 2>/dev/null | grep -aoiE "/Users/[a-z0-9._-]+|$(whoami)" | sort -u || true)"
  hdiutil detach "$STAGE/verify" -quiet 2>/dev/null || true
  if [ -n "$LEAKS" ]; then
    echo "REFUSING to ship: the disk image embeds local paths:"
    echo "$LEAKS"
    rm -f "$DMG"
    exit 1
  fi
  echo "==> Verified: no local paths embedded"
fi

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  echo "==> Signing DMG as $CODESIGN_IDENTITY"
  codesign --force --sign "$CODESIGN_IDENTITY" "$DMG"
fi

SIZE="$(du -h "$DMG" | cut -f1 | tr -d ' ')"
echo ""
echo "Built $DMG ($SIZE)"
shasum -a 256 "$DMG" | awk '{print "sha256: " $1}'
