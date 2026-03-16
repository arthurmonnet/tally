#!/bin/bash
set -e

# ── Config (sourced from gitignored file) ───────────────
source "$(dirname "$0")/release-config.sh"
# ────────────────────────────────────────────────────────

APP_NAME="Tally"
SCHEME="Tally"
BUNDLE_ID="com.arthurmonnet.tally"
BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

echo "── Clean ──"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "── Archive ──"
xcodebuild archive \
  -scheme "$SCHEME" \
  -archivePath "$ARCHIVE_PATH" \
  -configuration Release \
  CODE_SIGN_STYLE="manual" \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--options runtime"

echo "── Export ──"
cat > "$BUILD_DIR/ExportOptions.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"\>
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$BUILD_DIR" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist"

echo "── Create DMG ──"
if command -v create-dmg &> /dev/null; then
  create-dmg \
    --volname "$APP_NAME" \
    --volicon "$APP_PATH/Contents/Resources/AppIcon.icns" \
    --window-pos 200 120 \
    --window-size 600 400 \
    --icon-size 100 \
    --icon "$APP_NAME.app" 150 190 \
    --app-drop-link 450 190 \
    --hide-extension "$APP_NAME.app" \
    "$DMG_PATH" \
    "$APP_PATH"
else
  echo "create-dmg not found, using hdiutil..."
  STAGING="$BUILD_DIR/dmg-staging"
  mkdir -p "$STAGING"
  cp -R "$APP_PATH" "$STAGING/"
  ln -s /Applications "$STAGING/Applications"
  hdiutil create -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG_PATH"
  rm -rf "$STAGING"
fi

echo "── Notarize ──"
xcrun notarytool submit "$DMG_PATH" \
  --apple-id "$APPLE_ID" \
  --team-id "$TEAM_ID" \
  --password "$APP_PASSWORD" \
  --wait

echo "── Staple ──"
xcrun stapler staple "$DMG_PATH"

echo "── Verify ──"
xcrun stapler validate "$DMG_PATH"
spctl -a -t open --context context:primary-signature -v "$DMG_PATH"

echo ""
echo "✓ Done: $DMG_PATH"
echo "  Ready to upload to GitHub Releases."
