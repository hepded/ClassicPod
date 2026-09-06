#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION="${CONFIGURATION:-release}"
swift build -c "$CONFIGURATION"
BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP="$PWD/dist/ClassicPod.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ClassicPod" "$APP/Contents/MacOS/ClassicPod"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/LICENSE"
cp Support/ClassicPod.icns "$APP/Contents/Resources/ClassicPod.icns"
for localization in Support/*.lproj; do
    ditto "$localization" "$APP/Contents/Resources/$(basename "$localization")"
done
for bundle in "$BIN_DIR"/*.bundle; do
    [ -d "$bundle" ] || continue
    ditto "$bundle" "$APP/Contents/Resources/$(basename "$bundle")"
done
codesign --force --sign - --entitlements Support/ClassicPod.entitlements "$APP"
echo "$APP"
