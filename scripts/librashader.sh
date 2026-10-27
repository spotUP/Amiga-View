#!/bin/bash
# Builds the librashader C API (Metal runtime only) into build/librashader/:
# librashader.dylib (install name @rpath/librashader.dylib) and the C headers.
# Source is cloned to build/librashader-src at the pinned tag. build/ is git-ignored.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG=librashader-v0.12.1
SRC=build/librashader-src
OUT=build/librashader
if [ ! -d "$SRC/.git" ]; then
    mkdir -p build
    git clone --depth 1 --branch "$TAG" https://github.com/SnowflakePowered/librashader "$SRC"
fi
git -C "$SRC" tag --points-at HEAD | grep -qx "$TAG" \
    || { echo "error: $SRC is not at $TAG" >&2; exit 1; }
if [ ! -f "$OUT/librashader.dylib" ]; then
    (cd "$SRC" && cargo run -p librashader-build-script -- --profile optimized -- \
        --no-default-features --features runtime-metal)
    mkdir -p "$OUT"
    cp "$SRC/target/optimized/librashader.dylib" "$OUT/librashader.dylib"
    install_name_tool -id @rpath/librashader.dylib "$OUT/librashader.dylib"
    # install_name_tool invalidates the linker-applied ad-hoc signature
    codesign --force --sign - "$OUT/librashader.dylib"
fi
cp "$SRC"/include/librashader*.h "$OUT/"
echo "Built $OUT/librashader.dylib"
