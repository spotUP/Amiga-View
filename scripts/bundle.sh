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
# librashader (Metal filter chain), built by scripts/librashader.sh; found via @rpath
scripts/librashader.sh
mkdir -p "$APP/Contents/Frameworks"
cp build/librashader/librashader.dylib "$APP/Contents/Frameworks/librashader.dylib"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Amiga-View"
cp Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
# wasabi client for Amiga > Reset Amiga... (vendored, see Resources/wasabi/VENDORED.md)
cp Resources/wasabi/wasabi.py "$APP/Contents/Resources/wasabi.py"
# Mega Bezel shader presets for View > CRT Shader, fetched by scripts/fetch-shaders.sh
[ -d build/shaders ] || scripts/fetch-shaders.sh
cp -R build/shaders "$APP/Contents/Resources/shaders"
# Licence texts shipped with the third-party parts: librashader's MPL-2.0 (the dylib, unmodified) and
# the GPL-3.0 (Mega Bezel and slang-shaders), both taken from the librashader source scripts/librashader.sh fetched.
mkdir -p "$APP/Contents/Resources/shaders/licenses"
cp build/librashader-src/LICENSE.md "$APP/Contents/Resources/shaders/licenses/librashader-MPL-2.0.md"
cp build/librashader-src/LICENSE-GPL.md "$APP/Contents/Resources/shaders/licenses/GPL-3.0.md"
rm -rf build/AppIcon.iconset
swift scripts/make-icon.swift build/AppIcon.iconset
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
IDENTITY="${AMIGA_VIEW_IDENTITY:-Amiga-View Dev}"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$APP/Contents/Frameworks/librashader.dylib"
    codesign --force --sign "$IDENTITY" "$APP"
    # The grant only survives rebuilds when the requirement names the certificate, not a cdhash.
    codesign -dr - "$APP" 2>&1 | grep -q "certificate leaf" \
        || { echo "error: $APP designated requirement does not name the certificate" >&2; exit 1; }
else
    echo "warning: no \"$IDENTITY\" signing identity; signing ad-hoc (Accessibility must be granted again after every build)" >&2
    codesign --force --sign - "$APP/Contents/Frameworks/librashader.dylib"
    codesign --force --sign - "$APP"
fi
echo "Built $APP"
if [ "${1:-}" = "--release" ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
    ZIP="build/Amiga-View-$VERSION.zip"
    rm -f "$ZIP"
    ditto -c -k --keepParent "$APP" "$ZIP"
    echo "Packed $ZIP"
fi
