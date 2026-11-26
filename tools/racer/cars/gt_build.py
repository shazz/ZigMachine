"""The GT car (R82 M5 step 3): built as a Blender 5.3 scene by this script and exported by the add-on's Car Kit operator, as
an author would (its meter refuses a car over budget, then `kcar.export`). Original content (ours). The `.blend` is built at
need, never committed; the export is.

    ~/.local/blender/blender -b --factory-startup --python tools/racer/cars/gt_build.py -- tools/racer/cars/gt.kcar.json
"""

from __future__ import annotations

import sys
from pathlib import Path

import bpy

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parents[1]))  # this checkout's tools/ (never another checkout's)
sys.path.insert(0, str(HERE.parent / "tracks"))
sys.path.insert(0, str(HERE))
import gt_geom as g  # noqa: E402
import kit_scene  # noqa: E402
import racer.blender as kit  # noqa: E402
from racer.blender import car  # noqa: E402


def build() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc["kcar_name"] = "gt"
    sc["kcar_sun"] = list(g.SUN)
    mats = {n: kit_scene.material(n, c, False) for n, c in g.MATERIALS.items()}
    for part, make in g.PARTS.items():
        kit_scene.to_object(f"car_{part}", make(), mats)
    bpy.context.view_layer.update()


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args:
        raise SystemExit("usage: ... --python gt_build.py -- out.kcar.json [--blend out.blend]")
    build()
    kit.register()
    bpy.ops.kcar.meter()
    m = car._METER
    if m.get("error") or m.get("problems"):
        raise SystemExit(f"gt: over budget or broken: {m.get('error') or m['problems']}")
    if bpy.ops.kcar.export(filepath=args[0]) != {"FINISHED"}:
        raise SystemExit("gt: the export operator failed")
    print("gt: " + ", ".join(f"{label} {v}/{lim}" for label, v, lim, _ in m["rows"]) + f" -> {args[0]}")
    if "--blend" in args:
        bpy.ops.wm.save_as_mainfile(filepath=args[args.index("--blend") + 1])


main()
