#!/bin/bash
# Build GlobeSwitch.app from source and install it.
#   ./install.sh             build, copy to ~/Applications, make it a login item, hand 🌐 to it
#   ./install.sh uninstall   remove the login item and the app, and give 🌐 back to macOS
set -euo pipefail
cd "$(dirname "$0")"

APP="$HOME/Applications/GlobeSwitch.app"
LINK="$HOME/.local/bin/globe-switch"

if [[ "${1:-}" == "uninstall" ]]; then
    if [[ ! -x "$APP/Contents/MacOS/globe-switch" ]]; then
        scripts/build-app.sh - >/dev/null # an install from before 0.3 has no app to run
        APP=.build/GlobeSwitch.app
    fi
    exec "$APP/Contents/MacOS/globe-switch" uninstall
fi

# A certificate keeps the Input Monitoring grant across rebuilds; ad-hoc signatures do not.
IDENTITY="${GLOBE_SWITCH_IDENTITY:-Apple Development}"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    echo "no \"$IDENTITY\" signing identity; signing ad-hoc (grant Input Monitoring again after each rebuild)"
    IDENTITY=-
fi

scripts/build-app.sh "$IDENTITY"
.build/GlobeSwitch.app/Contents/MacOS/globe-switch install --no-doctor

# The command-line tool, for doctor and friends.
mkdir -p "$(dirname "$LINK")"
ln -sf "$APP/Contents/MacOS/globe-switch" "$LINK"
echo "linked $LINK"
echo
sleep 1
"$APP/Contents/MacOS/globe-switch" doctor || true
