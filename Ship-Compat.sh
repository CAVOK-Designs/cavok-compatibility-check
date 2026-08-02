#!/bin/bash
# Ship-Compat.sh — build, sign, notarize and package CAVOK Compatibility Check.
#
# This app is handed to STRANGERS on a public forum, so notarization is not
# optional: an un-notarized binary throws a Gatekeeper scare screen, and nobody
# doing you a favour should have to right-click-Open an unknown developer's app.
#
# Mirrors ~/Desktop/Bloom/Ship.sh (same Developer ID cert, same `CAVOK` notary
# profile), but builds from SPM rather than Xcode and hand-assembles the bundle.
#
# Usage:  ./Ship-Compat.sh            (build → sign → notarize → staple → zip)
#         ./Ship-Compat.sh --dry-run  (build + bundle, ad-hoc signed, no notarize)
set -euo pipefail

APP_NAME="CAVOK Compatibility Check"
BUNDLE_ID="com.cavokdesigns.compatcheck"
VERSION="1.0"
KEYCHAIN_PROFILE="CAVOK"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$HOME/Desktop/CAVOK_Compat_release"
APP="$OUT_DIR/$APP_NAME.app"
DRY_RUN=${1:-}

echo "▸ 1/6  Building release binary…"
cd "$SRC_DIR"
swift build -c release --arch arm64
BIN="$SRC_DIR/.build/arm64-apple-macosx/release/CavokCompat"
[ -f "$BIN" ] || { echo "✗ no binary at $BIN"; exit 1; }

echo "▸ 2/6  Assembling the .app bundle…"
rm -rf "$APP" "$OUT_DIR/$APP_NAME.zip"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CavokCompat"

# ── MLX Metal shaders ────────────────────────────────────────────────────────
# `swift build` does NOT compile .metal files — only Xcode does — so a plain SPM
# build of mlx-swift links fine and then dies at the first GPU dispatch with
# "Failed to load the default metallib". We compile the shader library by hand.
#
# -mmacosx-version-min=14.0 is load-bearing. Copying the metallib out of the
# shipping CAVOK.app would be easier, but that one is built for macOS 26; if it
# then failed to load on macOS 14 we would have manufactured a false negative and
# wrongly concluded MLX can't run there. The whole point of this app is to
# measure the 14.0 path, so the shaders must be built for it.
METAL_SRC="$SRC_DIR/.build/checkouts/mlx-swift/Source/Cmlx/mlx-generated"
AIR_DIR="$SRC_DIR/.build/metal-air"
BDL="$APP/Contents/Resources/mlx-swift_Cmlx.bundle"
rm -rf "$AIR_DIR"; mkdir -p "$AIR_DIR" "$BDL/Contents/Resources"

pushd "$METAL_SRC/metal" >/dev/null
# Recursive: steel_attention.metal lives in steel/attn/kernels/, and a flat
# *.metal glob silently drops it — producing a metallib that loads but is
# missing the attention kernels.
for f in $(find . -name "*.metal" | sort); do
  xcrun metal -c -mmacosx-version-min=14.0 -I. -I"$METAL_SRC" \
    -o "$AIR_DIR/$(basename "$f" .metal).air" "$f" 2>/dev/null
done
popd >/dev/null

COUNT=$(ls "$AIR_DIR"/*.air | wc -l | tr -d ' ')
EXPECTED=$(find "$METAL_SRC" -name "*.metal" | wc -l | tr -d ' ')
[ "$COUNT" == "$EXPECTED" ] || { echo "✗ compiled $COUNT of $EXPECTED shaders"; exit 1; }
xcrun metallib -o "$BDL/Contents/Resources/default.metallib" "$AIR_DIR"/*.air
echo "   $COUNT Metal shaders compiled for macOS 14.0"

cat > "$BDL/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>mlx-swift.Cmlx.resources</string>
    <key>CFBundleName</key><string>mlx-swift_Cmlx</string>
    <key>CFBundlePackageType</key><string>BNDL</string>
</dict>
</plist>
PLIST

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>        <string>CavokCompat</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>    <string>14.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSHumanReadableCopyright</key>  <string>CAVOK Designs</string>
</dict>
</plist>
PLIST

if [ "$DRY_RUN" == "--dry-run" ]; then
  echo "▸ 3/6  (dry run — ad-hoc signing, no notarization)"
  codesign --force --deep --sign - "$APP"
  echo "✓ Dry-run bundle at: $APP"
  exit 0
fi

echo "▸ 3/6  Signing with Developer ID…"
IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed 's/.*"\(.*\)"/\1/')
[ -n "$IDENTITY" ] || { echo "✗ No 'Developer ID Application' certificate found."; exit 1; }
echo "   $IDENTITY"

# Hardened Runtime is required for notarization. No entitlements file: this app
# deliberately has NO network, NO file access and NO JIT — the smallest possible
# ask of a volunteer tester, and something they can verify with `codesign -d`.
codesign --force --timestamp --options runtime --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=1 "$APP"

echo "▸ 4/6  Zipping for notarization…"
ZIP="$OUT_DIR/$APP_NAME.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ 5/6  Notarizing (usually 2–15 min)…"
xcrun notarytool submit "$ZIP" --keychain-profile "$KEYCHAIN_PROFILE" --wait

echo "▸ 6/6  Stapling and packaging for distribution…"
# Staple the notarization ticket INTO the app, so it validates even for a tester
# who is offline or behind a firewall that blocks Apple's ticket lookup.
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

# The download a stranger actually receives: the stapled app plus the plain-text
# explainer, in one folder. Notarization above ran on a bare zip of the app —
# the README is added afterwards so it can never confuse notarytool.
rm -f "$ZIP"
STAGE="$OUT_DIR/stage/$APP_NAME"
rm -rf "$OUT_DIR/stage"; mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
cp "$SRC_DIR/DIST_README.txt" "$STAGE/README.txt"
ditto -c -k --keepParent "$STAGE" "$ZIP"
rm -rf "$OUT_DIR/stage"

# Re-verify AFTER repackaging: proves the staple survived the copy, which is the
# state the tester will actually receive.
echo ""
echo "✓ Done."
echo "  App: $APP"
echo "  Zip: $ZIP   ← upload this"
echo ""
spctl --assess --type execute --verbose=2 "$APP" 2>&1 | sed 's/^/  /'
echo "  zip contents:"
unzip -l "$ZIP" | awk 'NR>3 && NF>3 {print "    "$4}' | head -5
