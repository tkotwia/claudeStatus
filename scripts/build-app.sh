#!/bin/bash
# Builds build/ClaudeStatus.app from the Swift package.
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP=build/ClaudeStatus.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ClaudeStatus "$APP/Contents/MacOS/ClaudeStatus"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP"
