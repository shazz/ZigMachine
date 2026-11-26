"""The Blender side shared by the generated track scenes after Salt Flats (R82 M5 step 2): materials, mesh objects, the start
grid, and the add-on's meter + export operator run as an author would. Runs inside Blender 5.3 (`bpy`).

    blender -b --factory-startup --python tools/racer/tracks/<name>_build.py -- out.ktrk.json [--blend out.blend]
"""

from __future__ import annotations

import math
import sys
from collections.abc import Callable
from pathlib import Path

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
import racer.blender as kit  # noqa: E402
from salt_flats_geom import Mesh  # noqa: E402


def material(name: str, rgb: tuple[int, int, int], dual: bool) -> bpy.types.Material:
    mat = bpy.data.materials.new(name)
    mat["ktrk_rgb"] = list(rgb)
    if dual:
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


def grid(st: list, z: list[float]) -> None:
    """8 slots, two a row behind the line, facing the travel direction (local +Y)."""
    root = bpy.data.objects.new("start_grid", None)
    bpy.context.scene.collection.objects.link(root)
    for k in range(8):
        i = (k + 1) // 2
        x, y, lx, ly = st[i]
        lat = 0.0 if k == 0 else (2.0 if k % 2 else -2.0)
        e = bpy.data.objects.new(f"slot{k}", None)
        e.location = (x - lx * lat, y - ly * lat, z[i])
        e.rotation_euler = (0.0, 0.0, math.atan2(-ly, -lx))
        e.parent = root
        bpy.context.scene.collection.objects.link(e)


def scene(props: dict[str, object], palette: dict[str, tuple[int, int, int]], dual: set[str], objects: dict[str, Mesh]) -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    for k, v in props.items():
        sc[f"ktrk_{k}"] = v
    mats = {n: material(n, c, n in dual) for n, c in palette.items()}
    for name, m in objects.items():
        to_object(name, m, mats)


def run(tag: str, build: Callable[[], None]) -> None:
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if not args:
        raise SystemExit(f"usage: ... --python {tag}_build.py -- out.ktrk.json [--blend out.blend]")
    build()
    bpy.context.view_layer.update()
    kit.register()  # through the add-on as an author would: its meter, then its export operator
    bpy.ops.ktrk.meter()
    meter = kit._METER
    if meter.get("error") or meter.get("problems"):
        raise SystemExit(f"{tag}: over budget or broken: {meter.get('error') or meter['problems']}")
    if bpy.ops.ktrk.export(filepath=args[0]) != {"FINISHED"}:
        raise SystemExit(f"{tag}: the export operator failed")
    print(f"{tag}: " + ", ".join(f"{label} {v}/{lim}" for label, v, lim, _ in meter["rows"]) + f" -> {args[0]}")
    if "--blend" in args:
        bpy.ops.wm.save_as_mainfile(filepath=args[args.index("--blend") + 1])
