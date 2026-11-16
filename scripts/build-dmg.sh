#!/bin/bash
# Builds build/SimpleMacEQ.dmg: the app plus an Applications shortcut to drag
# it onto.
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build-app.sh

STAGING="build/dmg"
DMG="build/SimpleMacEQ.dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R build/SimpleMacEQ.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname SimpleMacEQ -srcfolder "$STAGING" \
    -fs HFS+ -format UDZO -ov "$DMG"

rm -rf "$STAGING"

echo "Built $DMG"
