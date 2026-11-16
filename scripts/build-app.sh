#!/bin/bash
# Builds build/SimpleMacEQ.app from the Swift package.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/SimpleMacEQ.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/SimpleMacEQ" "$APP/Contents/MacOS/SimpleMacEQ"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: enough to run locally and to get the audio capture prompt.
codesign --force --sign - "$APP"

echo "Built $APP"
