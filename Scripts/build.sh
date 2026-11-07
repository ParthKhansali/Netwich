#!/usr/bin/env bash
# Full pipeline: unit tests, project generation, compile, assemble the bundle,
# and sign when an identity is available.
#
#   ./Scripts/build.sh                        # compile only (no signing, works anywhere)
#   CODE_SIGN_IDENTITY="Developer ID Application: …" ./Scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> swift test"
swift test

echo "==> xcodegen"
xcodegen generate --spec project.yml

echo "==> xcodebuild"
xcodebuild \
  -project Merge.xcodeproj \
  -scheme Merge \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

PRODUCTS=$(xcodebuild -project Merge.xcodeproj -scheme Merge -configuration Debug -showBuildSettings 2>/dev/null \
  | awk '/ BUILT_PRODUCTS_DIR/ {print $3; exit}')

if [ -d "$PRODUCTS/Netwich.app" ]; then
  APP="$PRODUCTS/Netwich.app"
else
  APP="$PRODUCTS/Merge.app"
fi

EXTENSION="$PRODUCTS/MergeProxy.systemextension"
DEST="$APP/Contents/Library/System Extensions"

# A system extension must live here for macOS to activate it.
echo "==> assemble"
mkdir -p "$DEST"
rm -rf "$DEST/MergeProxy.systemextension"
ditto "$EXTENSION" "$DEST/MergeProxy.systemextension"

# Build and bundle browser extension
echo "==> bundle browser extensions"
if command -v npx >/dev/null 2>&1; then
  npx esbuild extension/src/popup.ts --bundle --outfile=extension/chrome/popup.js --format=iife --platform=browser
  npx esbuild extension/src/options.ts --bundle --outfile=extension/chrome/options.js --format=iife --platform=browser
  npx esbuild extension/src/background.ts --bundle --outfile=extension/chrome/background.js --format=iife --platform=browser
  npx esbuild extension/src/content.ts --bundle --outfile=extension/chrome/content.js --format=iife --platform=browser
  cp extension/chrome/popup.html extension/firefox/popup.html
  cp extension/chrome/options.html extension/firefox/options.html
  cp extension/chrome/ui.css extension/firefox/ui.css
  cp extension/chrome/popup.js extension/firefox/popup.js
  cp extension/chrome/options.js extension/firefox/options.js
  cp extension/chrome/background.js extension/firefox/background.js
  cp extension/chrome/content.js extension/firefox/content.js
  cp extension/chrome/manifest.json extension/
  cp extension/chrome/*.html extension/
  cp extension/chrome/*.css extension/
  cp extension/chrome/*.js extension/
  cp -r extension/chrome/icons extension/
fi

# Embed browser extension bundle and brand assets into Resources
echo "==> embed extension & brand resources"
mkdir -p "$APP/Contents/Resources/extension"
ditto extension "$APP/Contents/Resources/extension"
if [ -d "App/Resources" ]; then
  ditto App/Resources "$APP/Contents/Resources"
fi
if [ -f "App/Resources/Netwich.icns" ]; then
  cp "App/Resources/Netwich.icns" "$APP/Contents/Resources/Netwich.icns"
fi

if [ -n "${CODE_SIGN_IDENTITY:-}" ]; then
  echo "==> sign"
  codesign --force --options runtime --timestamp \
    --entitlements Proxy/Proxy.entitlements \
    --identifier dev.parth.merge.proxy \
    -s "$CODE_SIGN_IDENTITY" "$DEST/MergeProxy.systemextension"
  codesign --force --options runtime --timestamp \
    --entitlements App/Netwich.entitlements \
    -s "$CODE_SIGN_IDENTITY" "$APP"
fi

echo "==> verify"
INFO="$DEST/MergeProxy.systemextension/Contents/Info.plist"
if [ -f "$INFO" ]; then
  /usr/libexec/PlistBuddy -c "Print :NSExtension:NSExtensionPointIdentifier" "$INFO" \
    || echo "WARNING: extension point missing from Info.plist"
else
  echo "WARNING: extension was not assembled"
fi

rm -rf build
mkdir -p build
ditto "$APP" build/Netwich.app
ln -sf Netwich.app build/Merge.app
du -sh build/Netwich.app
echo "==> build/Netwich.app is ready"
