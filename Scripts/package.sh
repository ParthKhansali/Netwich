#!/usr/bin/env bash
# Build a distributable Netwich release:
#
#   dist/Netwich-<version>.dmg                     drag-to-Applications installer
#   dist/Netwich-Extension-Chromium-<version>.zip  Chrome / Brave / Edge / Arc
#   dist/Netwich-Extension-Firefox-<version>.zip   Firefox
#   dist/Netwich-Extensions-<version>.zip          both, with a README
#
#   ./Scripts/package.sh                       # ad-hoc signed (works anywhere)
#   CODE_SIGN_IDENTITY="Developer ID Application: …" ./Scripts/package.sh
#   NOTARIZE=1 APPLE_ID=… TEAM_ID=… ./Scripts/package.sh
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' project.yml)
VERSION=${VERSION:-1.0.0}
DIST="dist"
BUILD="build"
APP="$BUILD/Netwich.app"
IDENTITY="${CODE_SIGN_IDENTITY:-}"

echo "==> Netwich $VERSION"

# ---------------------------------------------------------------- tests
echo "==> swift test"
swift test

# ---------------------------------------------------------------- project
echo "==> xcodegen"
xcodegen generate --spec project.yml

# ---------------------------------------------------------------- release build
echo "==> xcodebuild (Release)"
xcodebuild \
  -project Merge.xcodeproj \
  -scheme Merge \
  -configuration Release \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

PRODUCTS=$(xcodebuild -project Merge.xcodeproj -scheme Merge -configuration Release -showBuildSettings 2>/dev/null \
  | awk '/ BUILT_PRODUCTS_DIR/ {print $3; exit}')

BUILT_APP="$PRODUCTS/Netwich.app"
[ -d "$BUILT_APP" ] || { echo "error: $BUILT_APP was not produced"; exit 1; }

rm -rf "$BUILD"
mkdir -p "$BUILD" "$DIST"
touch "$BUILD/.metadata_never_index" "$DIST/.metadata_never_index"
ditto "$BUILT_APP" "$APP"

# ---------------------------------------------------------------- extensions
echo "==> browser extensions"
EXT_SRC="extension/chrome"
[ -d "$EXT_SRC" ] || { echo "error: $EXT_SRC is missing"; exit 1; }

# Keep Firefox in sync with the Chromium build (same compiled JS, different manifest).
if [ -d extension/firefox ]; then
  for f in popup.html options.html ui.css popup.js options.js background.js content.js; do
    [ -f "$EXT_SRC/$f" ] && cp "$EXT_SRC/$f" "extension/firefox/$f"
  done
  [ -d "$EXT_SRC/icons" ] && ditto "$EXT_SRC/icons" "extension/firefox/icons"
fi

mkdir -p "$APP/Contents/Resources/extensions"
ditto "$EXT_SRC" "$APP/Contents/Resources/extensions/chromium"
[ -d extension/firefox ] && ditto extension/firefox "$APP/Contents/Resources/extensions/firefox"

# Legacy location kept so older docs and the in-app "Reveal" button still resolve.
ditto extension "$APP/Contents/Resources/extension" 2>/dev/null || true

# ---------------------------------------------------------------- zip payloads
echo "==> extension archives"
rm -f "$DIST"/Netwich-Extension-*.zip "$DIST"/Netwich-Extensions-*.zip
ditto -c -k --sequesterRsrc --keepParent "$EXT_SRC" "$DIST/Netwich-Extension-Chromium-$VERSION.zip"
[ -d extension/firefox ] && ditto -c -k --sequesterRsrc --keepParent extension/firefox "$DIST/Netwich-Extension-Firefox-$VERSION.zip"

STAGE="$BUILD/extension-stage"
mkdir -p "$STAGE"
ditto "$EXT_SRC" "$STAGE/chromium"
[ -d extension/firefox ] && ditto extension/firefox "$STAGE/firefox"
cat > "$STAGE/INSTALL.txt" <<'TXT'
Netwich browser extension
=========================

Chromium (Chrome, Brave, Edge, Arc)
  1. Open chrome://extensions  (brave://extensions in Brave)
  2. Turn on Developer mode
  3. Load unpacked -> choose the "chromium" folder

Firefox
  1. Open about:debugging#/runtime/this-firefox
  2. Load Temporary Add-on... -> choose firefox/manifest.json
  Temporary add-ons are removed when Firefox quits. For a permanent install,
  sign the ZIP at https://addons.mozilla.org/developers/ or keep using the
  temporary load while developing.

The extension talks only to 127.0.0.1:19288-19290 on this Mac. Requests that
claim to come from a website are rejected by Netwich with 403.
TXT
ditto -c -k --sequesterRsrc --keepParent "$STAGE" "$DIST/Netwich-Extensions-$VERSION.zip"

# ---------------------------------------------------------------- signing
if [ -n "$IDENTITY" ]; then
  echo "==> signing with $IDENTITY"
  SIGN_ARGS=(--force --options runtime --timestamp --sign "$IDENTITY")
  SE="$APP/Contents/Library/System Extensions/MergeProxy.systemextension"
  if [ -d "$SE" ]; then
    codesign "${SIGN_ARGS[@]}" --entitlements Proxy/Proxy.entitlements --identifier dev.parth.merge.proxy "$SE"
  fi
  codesign "${SIGN_ARGS[@]}" --entitlements App/Netwich.entitlements "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP" || true
else
  echo "==> ad-hoc signing (no Developer ID configured)"
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

# ---------------------------------------------------------------- dmg
echo "==> disk image"
DMG_ROOT="$BUILD/dmg-root"
rm -rf "$DMG_ROOT"
mkdir -p "$DMG_ROOT"
ditto "$APP" "$DMG_ROOT/Netwich.app"
ln -s /Applications "$DMG_ROOT/Applications"

# A short note beside the app so nobody has to guess what the extra zips are for.
mkdir -p "$DMG_ROOT/Extensions"
cp "$DIST/Netwich-Extension-Chromium-$VERSION.zip" "$DMG_ROOT/Extensions/" 2>/dev/null || true
cp "$DIST/Netwich-Extension-Firefox-$VERSION.zip" "$DMG_ROOT/Extensions/" 2>/dev/null || true
cp "$STAGE/INSTALL.txt" "$DMG_ROOT/Extensions/INSTALL.txt" 2>/dev/null || true

DMG="$DIST/Netwich-$VERSION.dmg"
rm -f "$DMG"
hdiutil create \
  -volname "Netwich" \
  -srcfolder "$DMG_ROOT" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG" >/dev/null

# Best-effort window styling (icon positions, backdrop). Fails harmlessly on
# headless or automated sessions, which is why it is not fatal.
if [ -f App/Resources/dmg-background.png ]; then
  echo "==> styling installer window"
  RW="$BUILD/Netwich-rw.dmg"
  hdiutil convert "$DMG" -format UDRW -o "$RW" >/dev/null 2>&1 || true
  MOUNT=$(hdiutil attach "$RW" -readwrite -noverify -noautoopen 2>/dev/null | awk '/\/Volumes\// {print $3; exit}' || true)
  if [ -n "${MOUNT:-}" ]; then
    cp App/Resources/dmg-background.png "$MOUNT/.background.png" 2>/dev/null || true
    osascript <<APPLESCRIPT >/dev/null 2>&1 || true
tell application "Finder"
  tell disk "Netwich"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, 820, 540}
    set arrangement of icon view options of container window to not arranged
    set icon size of icon view options of container window to 120
    set background picture of icon view options of container window to file ".background.png"
    set position of item "Netwich.app" of container window to {170, 200}
    set position of item "Applications" of container window to {450, 200}
    close
  end tell
end tell
APPLESCRIPT
    hdiutil detach "$MOUNT" >/dev/null 2>&1 || true
    rm -f "$DMG"
    hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null 2>&1 || true
    rm -f "$RW"
  fi
fi

# ---------------------------------------------------------------- optional notarization
if [ "${NOTARIZE:-0}" = "1" ] && [ -n "$IDENTITY" ]; then
  echo "==> notarizing"
  xcrun notarytool submit "$DMG" --apple-id "${APPLE_ID:?}" --team-id "${TEAM_ID:?}" --password "${APP_PASSWORD:?}" --wait
  xcrun stapler staple "$DMG"
fi

echo ""
echo "==> done"
ls -lh "$DIST"
echo ""
echo "The app is unsigned unless CODE_SIGN_IDENTITY was set, so the first launch on"
echo "another Mac needs Privacy & Security -> Open Anyway. Netwich's onboarding"
echo "screen links straight to that pane."
