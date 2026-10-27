#!/bin/bash
# Builds the librashader C API (Metal runtime only) into build/librashader/:
# librashader.dylib (install name @rpath/librashader.dylib) and the C headers.
# Source is cloned to build/librashader-src at the pinned tag. build/ is git-ignored.
# The patches in patches/librashader/ are applied on top of the tag; the library is
# rebuilt whenever that set of patches changes.
set -euo pipefail
cd "$(dirname "$0")/.."
TAG=librashader-v0.12.1
SRC=build/librashader-src
OUT=build/librashader
PATCHES=patches/librashader
if [ ! -d "$SRC/.git" ]; then
    mkdir -p build
    git clone --depth 1 --branch "$TAG" https://github.com/SnowflakePowered/librashader "$SRC"
fi
git -C "$SRC" tag --points-at HEAD | grep -qx "$TAG" \
    || { echo "error: $SRC is not at $TAG" >&2; exit 1; }
for patch in "$PATCHES"/*.patch; do
    if git -C "$SRC" apply --reverse --check "$PWD/$patch" 2>/dev/null; then
        continue  # already applied
    fi
    git -C "$SRC" apply "$PWD/$patch" \
        || { echo "error: $patch does not apply to $SRC" >&2; exit 1; }
done
STAMP=$(cat "$PATCHES"/*.patch | shasum -a 256 | cut -d' ' -f1)
if [ ! -f "$OUT/librashader.dylib" ] || [ "$(cat "$OUT/patches.sha256" 2>/dev/null)" != "$STAMP" ]; then
    (cd "$SRC" && cargo run -p librashader-build-script -- --profile optimized -- \
        --no-default-features --features runtime-metal)
    mkdir -p "$OUT"
    cp "$SRC/target/optimized/librashader.dylib" "$OUT/librashader.dylib"
    install_name_tool -id @rpath/librashader.dylib "$OUT/librashader.dylib"
    # install_name_tool invalidates the linker-applied ad-hoc signature
    codesign --force --sign - "$OUT/librashader.dylib"
    echo "$STAMP" > "$OUT/patches.sha256"
fi
cp "$SRC"/include/librashader*.h "$OUT/"
echo "Built $OUT/librashader.dylib"
