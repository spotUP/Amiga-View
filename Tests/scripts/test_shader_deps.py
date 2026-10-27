"""Run: python3 -I -m unittest discover -s Tests/scripts   (from the repository root)"""
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "scripts", "shader_deps.py")
PRESETS = "bezel/Mega_Bezel/Presets"


def write(root, rel, text=""):
    path = os.path.join(root, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


class ShaderDepsTests(unittest.TestCase):
    def run_script(self, root):
        out = os.path.join(root, "out.txt")
        proc = subprocess.run([sys.executable, "-I", SCRIPT, root, PRESETS, out], capture_output=True, text=True)
        return proc, out

    def make_tree(self, root):
        write(root, PRESETS + "/MBZ__0__BASE.slangp",
              'shaders = 1\nshader0 = "../shaders/pass.slang"\ntextures = "LUT"\nLUT = "../textures/lut.png"\n')
        for i in range(1, 9):   # the other eight presets only point at the first
            write(root, PRESETS + "/MBZ__%d__X.slangp" % i, '#reference "MBZ__0__BASE.slangp"\n')
        write(root, "bezel/Mega_Bezel/shaders/pass.slang",
              '/* #include "commented.inc" */\n#include "inc/common.inc"\n#pragma include_optional "inc/absent.inc"\n')
        write(root, "bezel/Mega_Bezel/shaders/inc/common.inc", "// leaf\n")
        write(root, "bezel/Mega_Bezel/textures/lut.png", "png")
        write(root, "bezel/Mega_Bezel/shaders/unused.slang", "// not referenced\n")

    def test_returns_exactly_the_files_the_presets_reach(self):
        with tempfile.TemporaryDirectory() as root:
            self.make_tree(root)
            proc, out = self.run_script(root)
            self.assertEqual(proc.returncode, 0, proc.stderr)
            with open(out) as fh:
                got = fh.read().split()
        want = sorted([PRESETS + "/MBZ__%d__X.slangp" % i for i in range(1, 9)] + [
            PRESETS + "/MBZ__0__BASE.slangp",
            "bezel/Mega_Bezel/shaders/pass.slang",
            "bezel/Mega_Bezel/shaders/inc/common.inc",
            "bezel/Mega_Bezel/textures/lut.png",
        ])
        self.assertEqual(got, want)

    def test_missing_include_is_a_hard_error(self):
        with tempfile.TemporaryDirectory() as root:
            self.make_tree(root)
            os.remove(os.path.join(root, "bezel/Mega_Bezel/shaders/inc/common.inc"))
            proc, _ = self.run_script(root)
        self.assertNotEqual(proc.returncode, 0)
        self.assertIn("missing file", proc.stderr)


if __name__ == "__main__":
    unittest.main()
