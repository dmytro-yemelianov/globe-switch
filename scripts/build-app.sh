#!/bin/bash
# Build GlobeSwitch.app from the Swift package.
#   scripts/build-app.sh [signing identity] [output directory]
# The identity defaults to "-" (ad-hoc) and the output directory to .build.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${1:--}"
OUT="${2:-.build}"
APP="$OUT/GlobeSwitch.app"

# --disable-sandbox: Homebrew builds run inside its own sandbox, where SwiftPM's nested one fails.
# The package has no dependencies or plugins for the sandbox to contain.
swift build -c release --disable-sandbox --product globe-switch
BIN="$(swift build -c release --disable-sandbox --show-bin-path)/globe-switch"
VERSION="$("$BIN" --version)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/globe-switch"
sed "s/__VERSION__/$VERSION/g" App/Info.plist > "$APP/Contents/Info.plist"
cp App/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --options runtime --sign "$IDENTITY" "$APP"
echo "built $APP $VERSION, signed by ${IDENTITY/#-/ad-hoc}"
