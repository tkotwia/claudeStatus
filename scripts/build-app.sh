#!/bin/bash
# Builds build/ClaudeStatus.app from the Swift package.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/ClaudeStatus.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ClaudeStatus "$APP/Contents/MacOS/ClaudeStatus"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/MenuBarIcon.pdf "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

# launchd starts the binary directly, so nothing else tells Launch Services about the rebuilt
# bundle. Without this, notifications can keep showing the icon of an older build.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"

echo "Built $APP"
