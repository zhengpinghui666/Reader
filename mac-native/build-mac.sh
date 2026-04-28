#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="ReaderMacNative"
APP_DIR="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME-macOS.zip"
DMG_STAGING_DIR="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME-macOS.dmg"

cd "$ROOT_DIR"

swift build -c release --product "$APP_NAME"

BIN_DIR="$(swift build -c release --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$APP_NAME"

if [[ ! -f "$EXECUTABLE_PATH" ]]; then
  echo "Failed to locate built executable."
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

find "$ROOT_DIR/.build" -maxdepth 8 -type d -name "*.bundle" -exec cp -R {} "$APP_DIR/Contents/Resources/" \; || true

cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh_CN</string>
  <key>CFBundleExecutable</key>
  <string>ReaderMacNative</string>
  <key>CFBundleIdentifier</key>
  <string>com.binbyu.reader.macnative</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>ReaderMacNative</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" || echo "Warning: ad-hoc codesign failed; continuing unsigned."
fi

xattr -cr "$APP_DIR" >/dev/null 2>&1 || true

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

if command -v hdiutil >/dev/null 2>&1; then
  rm -rf "$DMG_STAGING_DIR"
  mkdir -p "$DMG_STAGING_DIR"
  cp -R "$APP_DIR" "$DMG_STAGING_DIR/"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"

  rm -f "$DMG_PATH"
  if hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"; then
    echo "DMG export completed."
  else
    echo "Warning: DMG export failed; zip export is still available."
  fi

  rm -rf "$DMG_STAGING_DIR"
else
  echo "hdiutil not found; skipping DMG export."
fi

echo ""
echo "ReaderMacNative.app exported to:"
echo "$APP_DIR"
echo ""
echo "ReaderMacNative zip exported to:"
echo "$ZIP_PATH"

if [[ -f "$DMG_PATH" ]]; then
  echo ""
  echo "ReaderMacNative dmg exported to:"
  echo "$DMG_PATH"
fi
