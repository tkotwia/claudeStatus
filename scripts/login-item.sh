#!/bin/bash
# Installs or removes the LaunchAgent that starts ClaudeStatus at login.
#   scripts/login-item.sh install
#   scripts/login-item.sh uninstall
set -euo pipefail
cd "$(dirname "$0")/.."

LABEL=local.claude-status
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
BINARY="$PWD/build/ClaudeStatus.app/Contents/MacOS/ClaudeStatus"
DOMAIN="gui/$(id -u)"

# Unloads the agent (which also stops the copy it started) and waits until launchd has let go
# of it; bootstrapping again too early fails with an I/O error.
unload() {
    launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true
    while launchctl print "$DOMAIN/$LABEL" >/dev/null 2>&1; do sleep 0.1; done
}

case "${1:-}" in
install)
    [ -x "$BINARY" ] || { echo "Build the app first: scripts/build-app.sh" >&2; exit 1; }
    unload
    # A copy started by hand would otherwise sit in the menu bar next to the one launchd starts.
    pkill -x -u "$(id -u)" ClaudeStatus 2>/dev/null || true
    while pgrep -x -u "$(id -u)" ClaudeStatus >/dev/null; do sleep 0.1; done

    mkdir -p "$(dirname "$PLIST")"
    # No KeepAlive: choosing "Quit" in the menu must really quit the app.
    # ProcessType Interactive keeps launchd from throttling the refresh timer.
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$BINARY</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>ProcessType</key>
    <string>Interactive</string>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
EOF
    launchctl bootstrap "$DOMAIN" "$PLIST"
    echo "Installed $PLIST (ClaudeStatus started)"
    ;;
uninstall)
    unload
    rm -f "$PLIST"
    echo "Removed $PLIST (ClaudeStatus stopped)"
    ;;
*)
    echo "usage: $0 install|uninstall" >&2
    exit 2
    ;;
esac
