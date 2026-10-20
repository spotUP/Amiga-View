#!/bin/bash
# Builds build/Amiga-View.app (release, ad-hoc signed).
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Amiga-View.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Amiga-View" "$APP/Contents/MacOS/Amiga-View"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
