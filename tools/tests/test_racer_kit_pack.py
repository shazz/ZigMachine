"""Kestrel Racing M7: the Track Kit packaged (tools/racer/kit_pack.py). The zip bundles exactly the add-on and what it imports,
runs WITHOUT the repository (a plain Python with only the unzipped kit on its path converts the sample to the same bytes),
and, where Blender 5.3 is installed, installs into an empty user directory as an extension and exports the sample's
generated .blend through its own operators (the committed export and the cart binary, byte for byte) and the GT car's
generated .blend through its .KCR button (= carc.py's file)."""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

from racer import carc, kit, kit_pack, ktrk
from racer.kcar_export import loads

ROOT = Path(__file__).resolve().parents[2]
SAMPLE = ROOT / "tools/racer/tracks/sample_oval.ktrk.json"
GT = ROOT / "tools/racer/cars/gt.kcar.json"
BLENDER = Path.home() / ".local/blender/blender"

TWIN = """
import sys, pathlib
from racer import kit, ktrk
assert pathlib.Path(kit.__file__).resolve().is_relative_to(pathlib.Path(sys.argv[1]).resolve()), kit.__file__
sys.stdout.buffer.write(kit.convert(ktrk.loads(pathlib.Path(sys.argv[2]).read_text())))
"""

INSTALLED = """
import sys, pathlib, addon_utils, bpy
here = pathlib.Path(sys.argv[sys.argv.index("--") + 1]).resolve()
assert addon_utils.check("bl_ext.user_default.kestrel_track_kit")[1], "the extension is not enabled"
import racer
assert pathlib.Path(racer.__file__).resolve().is_relative_to(here / "user"), racer.__file__
assert bpy.ops.ktrk.export(filepath=str(here / "out.ktrk.json")) == {"FINISHED"}
assert bpy.ops.ktrk.export_ktr(filepath=str(here / "OUT.KTR")) == {"FINISHED"}
print("INSTALLED OK", racer.__file__)
"""

CAR = """
import sys, pathlib, bpy
here = pathlib.Path(sys.argv[sys.argv.index("--") + 1]).resolve()
import racer
assert pathlib.Path(racer.__file__).resolve().is_relative_to(here / "user"), racer.__file__
assert bpy.ops.kcar.export_kcr(filepath=str(here / "OUT.KCR"), scale=2.0) == {"FINISHED"}
print("CAR OK")
"""


def blender(args: list[str], cwd: Path, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run([str(BLENDER), *args], cwd=cwd, env=env, capture_output=True, text=True, timeout=300, check=False)


class KitPackTest(unittest.TestCase):
    def test_the_zip_holds_the_addon_and_its_imports_and_nothing_of_the_local_import_tools(self) -> None:
        names = {p.relative_to(kit_pack.TOOLS).as_posix() for p in kit_pack.closure()}
        self.assertTrue({"racer/blender/__init__.py", "racer/blender/binary.py", "racer/blender/car.py",
                         "racer/blender/moodpanel.py", "racer/kit.py", "racer/carc.py", "racer/trackc.py"} <= names)
        self.assertEqual([n for n in names if Path(n).stem.startswith(("vr", "ref_", "test"))], [])

    def test_the_zip_is_deterministic_and_its_manifest_carries_the_addons_version_and_the_pending_licence(self) -> None:
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            za, zb = kit_pack.build(Path(a)), kit_pack.build(Path(b))
            self.assertEqual(za.read_bytes(), zb.read_bytes())
            man = zipfile.ZipFile(za).read("blender_manifest.toml").decode()
        self.assertIn(f'version = "{kit_pack.version()}"', man)
        self.assertIn('license = ["SPDX:LicenseRef-Pending"]', man)
        self.assertEqual(za.name, f"kestrel_track_kit-{kit_pack.version()}.zip")

    def test_a_missing_bl_info_is_refused_by_name(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            old, kit_pack.ADDON = kit_pack.ADDON, Path(tmp)
            (Path(tmp) / "__init__.py").write_text("x = 1\n")
            try:
                with self.assertRaisesRegex(SystemExit, "no bl_info"):
                    kit_pack.version()
            finally:
                kit_pack.ADDON = old

    def test_the_unzipped_kit_converts_the_sample_without_the_repository(self) -> None:
        want = kit.convert(ktrk.loads(SAMPLE.read_text()))
        with tempfile.TemporaryDirectory() as tmp:
            zipfile.ZipFile(kit_pack.build(Path(tmp))).extractall(Path(tmp) / "kit")
            env = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"} | {"PYTHONPATH": str(Path(tmp) / "kit")}
            got = subprocess.run([sys.executable, "-c", TWIN, str(Path(tmp) / "kit"), str(SAMPLE)], cwd=tmp, env=env,
                                 capture_output=True, check=True, timeout=120).stdout
        self.assertEqual(got, want)

    @unittest.skipUnless(BLENDER.is_file(), "Blender 5.3 is not installed here")
    def test_blender_installs_the_zip_and_its_operators_export_the_sample_and_the_gt(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            here = Path(tmp)
            env = {k: v for k, v in os.environ.items() if not k.startswith(("BLENDER_", "PYTHON"))}
            env["BLENDER_USER_RESOURCES"] = str(here / "user")
            zpath = kit_pack.build(here)
            self.assertIn("Success", blender(["-b", "--factory-startup", "--command", "extension", "validate", str(zpath)], here, env).stdout)
            r = blender(["-b", "--command", "extension", "install-file", "-r", "user_default", "-e", str(zpath)], here, env)
            self.assertIn("Installed", r.stdout, r.stderr)
            blend = kit_pack.sample(here)
            (here / "check.py").write_text(INSTALLED)
            r = blender(["-b", str(blend), "--python", str(here / "check.py"), "--", str(here)], here, env)
            self.assertIn("INSTALLED OK", r.stdout, r.stdout[-2000:] + r.stderr[-2000:])
            self.assertEqual((here / "out.ktrk.json").read_text(), SAMPLE.read_text())
            self.assertEqual((here / "OUT.KTR").read_bytes(), kit.convert(ktrk.loads(SAMPLE.read_text())))
            gt = here / "gt.blend"  # the GT's generated scene, through the installed Car Kit's .KCR button
            subprocess.run([str(BLENDER), "-b", "--factory-startup", "--python", str(ROOT / "tools/racer/cars/gt_build.py"), "--",
                            str(here / "gt.kcar.json"), "--blend", str(gt)], check=True, capture_output=True, timeout=300)
            (here / "car.py").write_text(CAR)
            r = blender(["-b", str(gt), "--python", str(here / "car.py"), "--", str(here)], here, env)
            self.assertIn("CAR OK", r.stdout, r.stdout[-2000:] + r.stderr[-2000:])
            self.assertEqual((here / "OUT.KCR").read_bytes(), carc.convert(loads(GT.read_text()), scale=2.0))


if __name__ == "__main__":
    unittest.main()
