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

# Build and bundle browser extension.
# The compiled JS is committed, so a missing node/esbuild/network must never fail
# the app build — it only means the TypeScript sources were not re-bundled.
echo "==> bundle browser extensions"
if command -v npx >/dev/null 2>&1 && [ -d extension/src ]; then
  for entry in popup options background content; do
    npx --yes esbuild "extension/src/$entry.ts" \
      --bundle --minify \
      --outfile="extension/chrome/$entry.js" \
      --format=iife --platform=browser \
      || echo "note: esbuild skipped $entry.ts (using committed bundle)"
  done

  for f in popup.html options.html ui.css popup.js options.js background.js content.js; do
    [ -f "extension/chrome/$f" ] && cp "extension/chrome/$f" "extension/firefox/$f"
  done
  [ -d extension/chrome/icons ] && ditto extension/chrome/icons extension/firefox/icons
fi

# Refresh the loose root copy that older docs point at, without clobbering the
# per-browser manifests.
for f in popup.html options.html ui.css popup.js options.js background.js content.js; do
  [ -f "extension/chrome/$f" ] && cp "extension/chrome/$f" "extension/$f"
 done 2>/dev/null || true

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
touch build/.metadata_never_index
ditto "$APP" build/Netwich.app
ln -sf Netwich.app build/Merge.app
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -u build/Netwich.app 2>/dev/null || true
du -sh build/Netwich.app
echo "==> build/Netwich.app is ready"
