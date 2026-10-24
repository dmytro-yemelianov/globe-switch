#!/bin/bash
# Build, sign and (re)load globe-switch as a per-user LaunchAgent, and hand the 🌐 key over to it.
#   ./install.sh             install or update
#   ./install.sh uninstall   remove the agent and give 🌐 back to macOS as it was before
set -euo pipefail
cd "$(dirname "$0")"

LABEL=dev.yemelianov.globe-switch
BIN="$HOME/.local/bin/globe-switch"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LEGACY_LOG="$HOME/Library/Logs/globe-switch.log" # before 0.2 the agent logged here
DOMAIN="gui/$(id -u)"

# TextInputMenuAgent and TextInputSwitcher read AppleFnUsageType once at launch; until they restart,
# macOS keeps toggling on 🌐 too and races globe-switch (the first tap after a pause bounces back).
# Both are relaunched on demand by launchd.
restart_input_agents() {
    killall -KILL TextInputSwitcher 2>/dev/null || true
    killall TextInputMenuAgent 2>/dev/null || true
}

set_fn_usage() {
    defaults write com.apple.HIToolbox AppleFnUsageType -int "$1"
    restart_input_agents
}

# Remember what 🌐 did before the first install, so uninstall can put it back. An install from
# before 0.2 set Do Nothing without recording the old value; uninstall then falls back to
# Change Input Source.
remember_fn_usage() {
    defaults read "$LABEL" PreviousFnUsageType >/dev/null 2>&1 && return
    local current
    if ! current=$(defaults read com.apple.HIToolbox AppleFnUsageType 2>/dev/null); then
        defaults write "$LABEL" PreviousFnUsageType -string unset
    elif [[ "$current" != 0 || ! -f "$PLIST" ]]; then
        defaults write "$LABEL" PreviousFnUsageType -int "$current"
    fi
}

restore_fn_usage() {
    local previous
    previous=$(defaults read "$LABEL" PreviousFnUsageType 2>/dev/null) || previous=1
    if [[ "$previous" == unset ]]; then
        defaults delete com.apple.HIToolbox AppleFnUsageType 2>/dev/null || true
        restart_input_agents
    else
        [[ "$previous" =~ ^[0-9]+$ ]] || previous=1
        set_fn_usage "$previous"
    fi
    defaults delete "$LABEL" 2>/dev/null || true
    case "$previous" in
        0) echo "🌐 is back to Do Nothing" ;;
        1) echo "🌐 is back to Change Input Source" ;;
        2) echo "🌐 is back to Show Emoji & Symbols" ;;
        3) echo "🌐 is back to Start Dictation" ;;
        *) echo "🌐 is back to the macOS default" ;;
    esac
}

if [[ "${1:-}" == "uninstall" ]]; then
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    rm -f "$PLIST" "$BIN" "$LEGACY_LOG"
    restore_fn_usage
    echo "uninstalled globe-switch"
    exit 0
fi

# A stable identity keeps the Input Monitoring grant across rebuilds; ad-hoc signatures do not.
IDENTITY="${GLOBE_SWITCH_IDENTITY:-Apple Development}"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "$IDENTITY"; then
    echo "no \"$IDENTITY\" signing identity; signing ad-hoc (re-grant Input Monitoring after each rebuild)"
    IDENTITY=-
fi

swift build -c release --product globe-switch
BUILT="$(swift build -c release --show-bin-path)/globe-switch"
codesign --force --sign "$IDENTITY" --identifier "$LABEL" "$BUILT"

remember_fn_usage
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
mkdir -p "$(dirname "$BIN")" "$(dirname "$PLIST")"
install -m 755 "$BUILT" "$BIN"

# The agent logs to the unified log, so launchd's stdout and stderr are not kept.
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
</dict>
</plist>
EOF

set_fn_usage 0 # 🌐 → Do Nothing; globe-switch handles it
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "installed $BIN as $LABEL"
echo
sleep 1
"$BIN" doctor || true
