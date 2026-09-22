#!/bin/bash
# Builds EasySpeech.app. No dependencies beyond the Xcode command line tools.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP="$ROOT/build/EasySpeech.app"
CONTENTS="$APP/Contents"

# An @Observable property that assigns to itself inside its own didSet recurses until the
# stack runs out — the macro turns it into a computed property, which removes Swift's usual
# re-entry suppression. It builds and lints clean, and crashes the moment the value changes.
# Shipped once, in 1.2.6. Never again.
echo "==> Checking for self-assigning didSet"
python3 - "$ROOT" <<'PYEOF'
import re, sys, pathlib
bad = []
for f in pathlib.Path(sys.argv[1], "Sources").rglob("*.swift"):
    src = f.read_text()
    for m in re.finditer(r"var (\w+)[^\n]*\{\n(\s*didSet \{[^}]*\})", src):
        name, block = m.group(1), m.group(2)
        if re.search(rf"\b{name}\s*=[^=]", block):
            bad.append(f"{f}: {name}")
if bad:
    print("  ERROR: property assigns to itself inside its own didSet:")
    for b in bad:
        print("   ", b)
    sys.exit(1)
PYEOF

echo "==> Compiling ($CONFIG)"
swift build -c "$CONFIG" --package-path "$ROOT"
BIN="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)/EasySpeech"

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN" "$CONTENTS/MacOS/EasySpeech"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

echo "==> Installing icon"
cp "$ROOT/EasySpeechArt/EasySpeech.icns" "$CONTENTS/Resources/AppIcon.icns"

# Status-item template images. Named so NSImage(named: "MenuBarIcon") picks the
# right scale for the display — there is no asset catalog in an SPM build.
MB="$ROOT/EasySpeechArt/Assets.xcassets/MenuBarIcon.imageset"
cp "$MB/MenuBarIcon@1x.png" "$CONTENTS/Resources/MenuBarIcon.png"
cp "$MB/MenuBarIcon@2x.png" "$CONTENTS/Resources/MenuBarIcon@2x.png"
cp "$MB/MenuBarIcon@3x.png" "$CONTENTS/Resources/MenuBarIcon@3x.png"

echo "==> Signing"
# Ad-hoc signature. Enough for the microphone and speech permission prompts to work
# locally; replace "-" with your Developer ID to distribute.
codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" \
  --entitlements "$ROOT/Resources/EasySpeech.entitlements" \
  --options runtime \
  "$APP" 2>/dev/null \
  || codesign --force --deep --sign "${CODESIGN_IDENTITY:--}" \
       --entitlements "$ROOT/Resources/EasySpeech.entitlements" "$APP"

# Let Launch Services notice the document types right away.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
  -f "$APP" 2>/dev/null || true

echo ""
echo "Built $APP"
echo "Run it:      open '$APP'"
echo "Install it:  cp -R '$APP' /Applications/"
