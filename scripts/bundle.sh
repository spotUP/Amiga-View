#!/bin/bash
# Builds build/Amiga-View.app (release), signed with the "Amiga-View Dev" identity when the
# keychain has it. macOS ties the Accessibility grant (needed to post the Synergy hotkey) to the
# signature's designated requirement: an ad-hoc signature's is its cdhash, which every rebuild
# changes, so the grant would be lost; a certificate's stays the same across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP=build/Amiga-View.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/Amiga-View" "$APP/Contents/MacOS/Amiga-View"
cp Resources/Info.plist "$APP/Contents/Info.plist"
IDENTITY="${AMIGA_VIEW_IDENTITY:-Amiga-View Dev}"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$APP"
    # The grant only survives rebuilds when the requirement names the certificate, not a cdhash.
    codesign -dr - "$APP" 2>&1 | grep -q "certificate leaf" \
        || { echo "error: $APP designated requirement does not name the certificate" >&2; exit 1; }
else
    echo "warning: no \"$IDENTITY\" signing identity; signing ad-hoc (Accessibility must be granted again after every build)" >&2
    codesign --force --sign - "$APP"
fi
echo "Built $APP"
