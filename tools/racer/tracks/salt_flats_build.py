"""Salt Flats (R82 M5): a dry-lake speedway at noon, built as a Blender scene by this script, then exported by the Track Kit
add-on. Original content (ours): a wide, fast, flat loop with one sweeping bay, low barriers, a grandstand, a timing tower,
pylons and three low buttes on the lake. The `.blend` is built at need, never committed; the export is.

    blender -b --factory-startup --python tools/racer/tracks/salt_flats_build.py -- tools/racer/tracks/salt_flats.ktrk.json [--blend out.blend]
"""

from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import racer.blender as kit  # noqa: E402
from salt_flats_geom import DUAL, PALETTE, Mesh, decals, props, road, stations  # noqa: E402

def material(name: str, rgb: tuple[int, int, int]) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat["ktrk_rgb"] = list(rgb)
    if name in DUAL:
        mat["ktrk_dual"] = 1
    mat.diffuse_color = (*[(c / 255) ** 2.2 for c in rgb], 1.0)
    return mat


def to_object(name: str, m: Mesh, mats: dict[str, bpy.types.Material]) -> None:
    me = bpy.data.meshes.new(name)
    me.from_pydata(m.verts, [], m.faces)
    order = sorted(set(m.mats))
    for n in order:
        me.materials.append(mats[n])
    for p, n in zip(me.polygons, m.mats, strict=True):
        p.material_index = order.index(n)
    me.update()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    for g, ids in sorted(m.groups.items()):
        ob.vertex_groups.new(name=g).add(sorted(ids), 1.0, "REPLACE")


def grid(st: list) -> None:
    root = bpy.data.objects.new("start_grid", None)
    bpy.context.scene.collection.objects.link(root)
    for k in range(8):
        x, y, lx, ly = st[(k + 1) // 2]
        lat = 0.0 if k == 0 else (2.0 if k % 2 else -2.0)  # metres right of the line
        e = bpy.data.objects.new(f"slot{k}", None)
        e.location = (x - lx * lat, y - ly * lat, 0.0)
        e.rotation_euler = (0.0, 0.0, math.atan2(-ly, -lx))  # local +Y = (-sin, cos) along the travel direction
        e.parent = root
        bpy.context.scene.collection.objects.link(e)


def build() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc["ktrk_name"], sc["ktrk_mood"], sc["ktrk_sun"], sc["ktrk_far_ground"] = "salt_flats", "noon", (0.3, -0.4, 1.0), "salt"
    mats = {n: material(n, c) for n, c in PALETTE.items()}
    st = stations()
    m = Mesh()
    road(m, st)
    to_object("track", m, mats)
    d = Mesh()
    decals(d, st)
    to_object("decals", d, mats)
    p = Mesh()
    props(p, st)
    to_object("props", p, mats)
    grid(st)
    bpy.context.view_layer.update()


def main() -> None:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args:
        raise SystemExit("usage: ... --python salt_flats_build.py -- out.ktrk.json [--blend out.blend]")
    build()
    kit.register()  # through the add-on as an author would: its meter, then its export operator
    if "filepath" not in bpy.ops.ktrk.export.get_rna_type().properties:
        raise SystemExit("the add-on's export operator has no filepath property")
    bpy.ops.ktrk.meter()
    meter = kit._METER
    if meter.get("error") or meter.get("problems"):
        raise SystemExit(f"salt_flats: over budget or broken: {meter.get('error') or meter['problems']}")
    if bpy.ops.ktrk.export(filepath=args[0]) != {"FINISHED"}:
        raise SystemExit("salt_flats: the export operator failed")
    print("salt_flats: " + ", ".join(f"{label} {v}/{lim}" for label, v, lim, _ in meter["rows"]) + f" -> {args[0]}")
    if "--blend" in args:
        bpy.ops.wm.save_as_mainfile(filepath=args[args.index("--blend") + 1])


main()
