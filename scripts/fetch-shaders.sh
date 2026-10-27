#!/usr/bin/env bash
# Fetch the libretro slang-shaders at a pinned commit and copy the exact set of
# files the Mega Bezel presets need into build/shaders (tree layout kept).
set -euo pipefail

REPO_URL="${SLANG_SHADERS_URL:-https://github.com/libretro/slang-shaders}"
COMMIT="cb8e5341db3bb6ef4a34003f581c831eb8bd6cf2"
PRESET_DIR="bezel/Mega_Bezel/Presets"

here="$(cd "$(dirname "$0")" && pwd)"
root="$(dirname "$here")"
src="$root/build/slang-shaders"
dst="$root/build/shaders"

if [ "$(git -C "$src" rev-parse HEAD 2>/dev/null || true)" = "$COMMIT" ]; then
  echo "[INFO] slang-shaders already at $COMMIT"
else
  rm -rf "$src"
  mkdir -p "$src"
  git -C "$src" init -q
  git -C "$src" remote add origin "$REPO_URL"
  git -C "$src" fetch -q --depth 1 origin "$COMMIT"
  git -C "$src" -c advice.detachedHead=false checkout -q FETCH_HEAD
  [ "$(git -C "$src" rev-parse HEAD)" = "$COMMIT" ] || { echo "[ERROR] wrong commit" >&2; exit 1; }
fi

list="$(mktemp)"
trap 'rm -f "$list"' EXIT
python3 -I "$here/shader_deps.py" "$src" "$PRESET_DIR" "$list"

rm -rf "$dst"
mkdir -p "$dst"
# Tree layout kept; tar preserves relative paths.
tar -C "$src" -cf - -T "$list" | tar -C "$dst" -xf -

# Licences: slang-shaders root licence files (if any) and Mega Bezel's own.
mkdir -p "$dst/licenses"
found=0
for f in "$src"/LICENSE* "$src"/COPYING* "$src"/license*; do
  [ -f "$f" ] && { cp "$f" "$dst/licenses/slang-shaders-$(basename "$f")"; found=1; }
done
[ "$found" = 1 ] || echo "[INFO] slang-shaders has no root licence file at this commit; per-file headers apply"
for f in "$src"/bezel/Mega_Bezel/LICENSE* "$src"/bezel/Mega_Bezel/COPYING* "$src"/bezel/Mega_Bezel/README*; do
  [ -f "$f" ] && cp "$f" "$dst/licenses/MegaBezel-$(basename "$f")"
done
[ -f "$dst/licenses/MegaBezel-README.md" ] || { echo "[ERROR] Mega Bezel README missing" >&2; exit 1; }

(cd "$dst" && find . -type f ! -name MANIFEST.txt | sed 's|^\./||' | LC_ALL=C sort > MANIFEST.txt)
echo "[OK] $(wc -l < "$dst/MANIFEST.txt" | tr -d ' ') files, $(du -sk "$dst" | cut -f1) KiB in $dst"
