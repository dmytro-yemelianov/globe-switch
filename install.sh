#!/bin/bash
# Build, sign and (re)load globe-switch as a per-user LaunchAgent, and hand the 🌐 key over to it.
#   ./install.sh             install or update
#   ./install.sh uninstall   remove the agent and give 🌐 back to macOS
set -euo pipefail
cd "$(dirname "$0")"

LABEL=dev.yemelianov.globe-switch
BIN="$HOME/.local/bin/globe-switch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/globe-switch.log"
DOMAIN="gui/$(id -u)"
# A stable identity keeps the Input Monitoring grant across rebuilds; ad-hoc signatures do not.
IDENTITY="${GLOBE_SWITCH_IDENTITY:-Apple Development}"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    echo "no \"$IDENTITY\" signing identity; signing ad-hoc (re-grant Input Monitoring after each rebuild)"
    IDENTITY=-
fi

# TextInputMenuAgent and TextInputSwitcher read AppleFnUsageType once at launch; until they restart,
# macOS keeps toggling on 🌐 too and races globe-switch (the first tap after a pause bounces back).
# Both are relaunched on demand by launchd.
set_fn_usage() {
    defaults write com.apple.HIToolbox AppleFnUsageType -int "$1"
    killall -KILL TextInputSwitcher 2>/dev/null || true
    killall TextInputMenuAgent 2>/dev/null || true
}

if [[ "${1:-}" == "uninstall" ]]; then
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST" "$BIN"
    set_fn_usage 1 # 🌐 → Change Input Source
    echo "uninstalled; 🌐 is back to macOS's input source switcher"
    exit 0
fi

mkdir -p build "$(dirname "$BIN")"
swiftc -O -o build/globe-switch GlobeSwitch.swift
codesign --force --sign "$IDENTITY" --identifier "$LABEL" build/globe-switch

launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
install -m 755 build/globe-switch "$BIN"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BIN</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
EOF

set_fn_usage 0 # 🌐 → Do Nothing; globe-switch handles it
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "installed $BIN as $LABEL (log: $LOG)"
