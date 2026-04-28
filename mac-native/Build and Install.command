#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="ReaderMacNative"
APP_SRC="$ROOT_DIR/dist/$APP_NAME.app"
APP_DEST="/Applications/$APP_NAME.app"

cd "$ROOT_DIR"

chmod +x "$ROOT_DIR/build-mac.sh"
"$ROOT_DIR/build-mac.sh"

if [[ ! -d "$APP_SRC" ]]; then
  echo "Build finished, but $APP_SRC was not found."
  exit 1
fi

echo ""
echo "Installing $APP_NAME to /Applications..."
rm -rf "$APP_DEST"
ditto "$APP_SRC" "$APP_DEST"

xattr -cr "$APP_DEST" >/dev/null 2>&1 || true
chmod +x "$APP_DEST/Contents/MacOS/$APP_NAME"

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DEST" || echo "Warning: ad-hoc codesign failed; continuing unsigned."
fi

echo ""
echo "$APP_NAME installed to:"
echo "$APP_DEST"
echo ""
echo "Opening $APP_NAME..."
open "$APP_DEST"
