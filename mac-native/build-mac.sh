#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="ReaderMacNative"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DIST_LABEL="${READER_DIST_LABEL:-macOS}"
ZIP_PATH="$DIST_DIR/$APP_NAME-$DIST_LABEL.zip"
TAR_PATH="$DIST_DIR/$APP_NAME-$DIST_LABEL.tar.gz"
PKG_PATH="$DIST_DIR/$APP_NAME-$DIST_LABEL.pkg"
DMG_STAGING_DIR="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME-$DIST_LABEL.dmg"

cd "$ROOT_DIR"

BUILD_ARGS=(-c release --product "$APP_NAME")
if [[ -n "${READER_ARCHES:-}" ]]; then
  for arch in $READER_ARCHES; do
    BUILD_ARGS+=(--arch "$arch")
  done
fi

echo "macOS build host:"
uname -a || true
if command -v xcodebuild >/dev/null 2>&1; then
  xcodebuild -version || true
fi

if [[ -n "${READER_ARCHES:-}" ]]; then
  echo "Requested architecture(s): $READER_ARCHES"
fi

rm -rf "$ROOT_DIR/.build"
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
EXECUTABLE_PATH="$BIN_DIR/$APP_NAME"
if [[ ! -f "$EXECUTABLE_PATH" ]]; then
  EXECUTABLE_PATH="$(find "$ROOT_DIR/.build" -type f -name "$APP_NAME" | grep -E '/(Release|release)/' | head -n 1 || true)"
fi

if [[ ! -f "$EXECUTABLE_PATH" ]]; then
  echo "Failed to locate built executable."
  exit 1
fi

echo "Built executable:"
echo "$EXECUTABLE_PATH"
file "$EXECUTABLE_PATH" || true
if command -v lipo >/dev/null 2>&1; then
  lipo -info "$EXECUTABLE_PATH" || true
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$EXECUTABLE_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"
printf "APPL????" > "$APP_DIR/Contents/PkgInfo"

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
  <key>CFBundleSupportedPlatforms</key>
  <array>
    <string>MacOSX</string>
  </array>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR" || echo "Warning: ad-hoc codesign failed; continuing unsigned."
  codesign --verify --deep --strict --verbose=2 "$APP_DIR" || echo "Warning: codesign verification failed."
fi

xattr -cr "$APP_DIR" >/dev/null 2>&1 || true
ls -l "$APP_DIR/Contents/MacOS"

rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

rm -f "$TAR_PATH"
tar -czf "$TAR_PATH" -C "$DIST_DIR" "$APP_NAME.app"

if command -v pkgbuild >/dev/null 2>&1; then
  rm -f "$PKG_PATH"
  pkgbuild --component "$APP_DIR" --install-location /Applications "$PKG_PATH" || echo "Warning: pkg export failed."
else
  echo "pkgbuild not found; skipping PKG export."
fi

if command -v hdiutil >/dev/null 2>&1; then
  rm -rf "$DMG_STAGING_DIR"
  mkdir -p "$DMG_STAGING_DIR"
  cp -R "$APP_DIR" "$DMG_STAGING_DIR/"
  ln -s /Applications "$DMG_STAGING_DIR/Applications"
  cat > "$DMG_STAGING_DIR/Fix and Open Reader.command" <<'SCRIPT'
#!/bin/bash
set -euo pipefail

APP_NAME="ReaderMacNative"
APP_PATH="/Applications/$APP_NAME.app"
EXECUTABLE="$APP_PATH/Contents/MacOS/$APP_NAME"

echo "ReaderMacNative fix and open"
echo ""
sw_vers || true
echo "CPU: $(uname -m)"
echo ""

if [[ ! -d "$APP_PATH" ]]; then
  echo "$APP_PATH was not found."
  echo "Drag ReaderMacNative.app to Applications first, then run this command again."
  echo ""
  read -n 1 -s -r -p "Press any key to close..."
  exit 1
fi

xattr -cr "$APP_PATH" >/dev/null 2>&1 || true
chmod +x "$EXECUTABLE"

echo "Executable:"
ls -l "$EXECUTABLE"
file "$EXECUTABLE" || true
echo ""

if command -v codesign >/dev/null 2>&1; then
  codesign --verify --deep --strict --verbose=2 "$APP_PATH" || true
fi

echo ""
echo "Opening $APP_NAME..."
open "$APP_PATH"
echo ""
read -n 1 -s -r -p "Press any key to close..."
SCRIPT
  chmod +x "$DMG_STAGING_DIR/Fix and Open Reader.command"

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

echo ""
echo "ReaderMacNative tar exported to:"
echo "$TAR_PATH"

if [[ -f "$PKG_PATH" ]]; then
  echo ""
  echo "ReaderMacNative pkg exported to:"
  echo "$PKG_PATH"
fi

if [[ -f "$DMG_PATH" ]]; then
  echo ""
  echo "ReaderMacNative dmg exported to:"
  echo "$DMG_PATH"
fi
