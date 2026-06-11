#!/usr/bin/env bash
# Builds a distributable DMG from a built Wallsy.app.
# Usage: ./scripts/make_dmg.sh [version] [path/to/Wallsy.app]
#   ./scripts/make_dmg.sh            -> Wallsy-dev.dmg
#   ./scripts/make_dmg.sh v1.0.0     -> Wallsy-v1.0.0.dmg
set -euo pipefail

VERSION="${1:-dev}"
APP_ARG="${2:-}"

if [[ -n "$APP_ARG" ]]; then
  APP="$APP_ARG"
else
  # Find the most recent Release build (local Xcode or CI DerivedData).
  APP=$(ls -dt \
    "$HOME"/Library/Developer/Xcode/DerivedData/NaviPlay-*/Build/Products/Release/Wallsy.app \
    DerivedData/Build/Products/Release/Wallsy.app 2>/dev/null | head -1 || true)
fi

if [[ -z "${APP:-}" || ! -d "$APP" ]]; then
  echo "error: Wallsy.app not found. Build it first (NO sudo!):"
  echo "  xcodebuild -project NaviPlay.xcodeproj -scheme NaviPlay -configuration Release build"
  exit 1
fi

echo "Packaging: $APP"
OUT="Wallsy-${VERSION}.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Wallsy" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
echo "Created $OUT"
