#!/bin/bash
# Builds build/SimpleMacEQ.app.
#
# Calls swiftc directly instead of `swift build`, so it also works with
# Command Line Tools installs whose Swift package manager is broken.
set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="$(uname -m)-apple-macosx14.2"
OBJ="build/obj"
APP="build/SimpleMacEQ.app"

rm -rf "$OBJ" "$APP"
mkdir -p "$OBJ" "$APP/Contents/MacOS"

# 1. EQCore as a static library + module.
swiftc -O -target "$TARGET" -swift-version 5 \
    -parse-as-library \
    -module-name EQCore \
    -emit-module -emit-module-path "$OBJ/EQCore.swiftmodule" \
    -emit-library -static -o "$OBJ/libEQCore.a" \
    Sources/EQCore/*.swift

# 2. The app executable, linked against EQCore.
swiftc -O -target "$TARGET" -swift-version 5 \
    -parse-as-library \
    -module-name SimpleMacEQ \
    -I "$OBJ" -L "$OBJ" -lEQCore \
    -o "$APP/Contents/MacOS/SimpleMacEQ" \
    Sources/SimpleMacEQ/*.swift

cp Support/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature: enough to run locally and to get the audio capture prompt.
codesign --force --sign - "$APP"

echo "Built $APP"
