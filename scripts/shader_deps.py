"""Compute the closure of files needed by the Mega Bezel presets.

Usage: python3 -I shader_deps.py <slang-shaders-root> <preset-dir-relative> <out-list>

Follows #reference lines and shaderN / texture paths in .slangp/.params files and
#include lines in .slang/.inc/.h files. Paths are resolved relative to the
referencing file and normalised; a missing file is a hard error.
"""
import os
import re
import sys

PRESET_GLOB = re.compile(r"^MBZ__.*\.slangp$")
REF = re.compile(r'^\s*#reference\s+"?([^"\r\n]+?)"?\s*$')
KV = re.compile(r'^\s*([A-Za-z0-9_.\-]+)\s*=\s*"?([^"\r\n]*?)"?\s*(?://.*)?$')
INC = re.compile(r'^\s*#\s*include\s+"([^"]+)"')
INC_OPT = re.compile(r'^\s*#\s*pragma\s+include_optional\s+"([^"]+)"')
BLOCK = re.compile(r"/\*.*?\*/", re.S)
FILE_EXT = (".png", ".jpg", ".jpeg", ".tga", ".bmp", ".slang", ".slangp", ".params", ".cfg", ".inc", ".h")


def fail(msg):
    sys.stderr.write("ERROR: " + msg + "\n")
    sys.exit(1)


def resolve(root, from_file, rel):
    base = os.path.dirname(from_file)
    p = os.path.normpath(os.path.join(base, rel))
    if p.startswith("..") or os.path.isabs(p):
        fail("%s: path escapes the tree: %s" % (from_file, rel))
    return p


def main():
    root, preset_dir, out = sys.argv[1:4]
    seen = set()
    stack = []
    for name in sorted(os.listdir(os.path.join(root, preset_dir))):
        if PRESET_GLOB.match(name):
            stack.append(os.path.join(preset_dir, name))
    if len(stack) != 9:
        fail("expected 9 MBZ__ presets, found %d" % len(stack))

    def push(path, src, optional=False):
        if not os.path.isfile(os.path.join(root, path)):
            if optional:
                return
            fail("%s references missing file %s" % (src, path))
        if path not in seen:
            seen.add(path)
            stack.append(path)

    for p in list(stack):
        seen.add(p)
    while stack:
        cur = stack.pop()
        with open(os.path.join(root, cur), encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        if cur.endswith((".slangp", ".params")):
            tex_names = set()
            kvs = {}
            for line in text.splitlines():
                m = REF.match(line)
                if m:
                    push(resolve(root, cur, m.group(1)), cur)
                    continue
                if line.lstrip().startswith(("#", "//")):
                    continue
                m = KV.match(line)
                if m:
                    kvs[m.group(1)] = m.group(2)
            for k, v in kvs.items():
                if k == "textures":
                    tex_names.update(n for n in v.split(";") if n)
                elif re.fullmatch(r"shader\d+", k):
                    push(resolve(root, cur, v), cur)
            for n in tex_names:
                if n not in kvs:
                    fail("%s: texture %s has no path" % (cur, n))
                push(resolve(root, cur, kvs[n]), cur)
        elif cur.endswith((".slang", ".inc", ".h")):
            for line in BLOCK.sub("", text).splitlines():
                m = INC.match(line)
                if m:
                    push(resolve(root, cur, m.group(1)), cur)
                    continue
                m = INC_OPT.match(line)
                if m and not m.group(1).startswith("path/to"):
                    push(resolve(root, cur, m.group(1)), cur, optional=True)
    with open(out, "w") as fh:
        fh.write("\n".join(sorted(seen)) + "\n")


main()
