"""Kestrel Racing Track Kit: the Blender add-on (R82 M5, ours, MIT). Blender 5.3.

Exports the scene as the neutral `.ktrk.json` (and nothing else: the converter, tools/racer/kit.py, runs without Blender) and
shows a live budget meter in the 3D view's sidebar (N panel, "Track Kit" tab). The conventions are in
tools/racer/kit_export.py; docs/ports/kestrel_racing/M5.md is the manual.

From the repo (the add-on imports the pure modules from tools/racer/):
    blender -b scene.blend --python-expr "import sys; sys.path.insert(0, 'tools'); import racer.blender as k; k.export_to('out.ktrk.json')"
"""

import sys
from pathlib import Path
from typing import Any

import bpy

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))  # tools/: the add-on runs from the repo checkout

from racer import budget, kit_export, ktrk, limits  # noqa: E402

bl_info = {"name": "Kestrel Racing Track Kit", "author": "ZigMachine", "version": (1, 0, 0), "blender": (5, 3, 0),
           "location": "View3D > Sidebar > Track Kit", "description": "Export .ktrk.json tracks with a budget meter",
           "category": "Import-Export"}


def _mesh(ob: Any) -> dict[str, Any]:  # WHY: bpy objects are untyped
    me, mw = ob.data, ob.matrix_world
    rot = mw.to_3x3()
    names = [g.name for g in ob.vertex_groups]
    groups: dict[str, list[int]] = {}
    for v in me.vertices:
        for g in v.groups:
            if g.weight > 0:
                groups.setdefault(names[g.group], []).append(v.index)
    slots = [s.material.name if s.material else "" for s in ob.material_slots]
    faces = [{"v": list(p.vertices), "mat": slots[p.material_index] if slots else "",
              "normal": list((rot @ p.normal).normalized())} for p in me.polygons]
    return {"name": ob.name, "verts": [list(mw @ v.co) for v in me.vertices], "faces": faces,
            "edges": [list(e.vertices) for e in me.edges], "groups": groups}


def extract(scene: Any) -> kit_export.Scene:  # WHY: bpy scene is untyped
    obs = sorted(scene.objects, key=lambda o: o.name)
    mats = {m.name: {"rgb": [int(c) for c in m["ktrk_rgb"]], "dual": bool(m.get("ktrk_dual", 0))}
            for m in bpy.data.materials if "ktrk_rgb" in m}
    grid = [{"name": o.name, "pos": list(o.matrix_world.translation), "rot_z": o.matrix_world.to_euler().z}
            for o in obs if o.parent is not None and o.parent.name == "start_grid"]
    return {"objects": [_mesh(o) for o in obs if o.type == "MESH"], "materials": mats, "grid": grid,
            "scene": {"name": str(scene.get("ktrk_name", scene.name)), "mood": str(scene.get("ktrk_mood", "noon")),
                      "sun": [float(c) for c in scene.get("ktrk_sun", (0.0, 0.0, 1.0))],
                      "far_ground": str(scene.get("ktrk_far_ground", "")), **_look(scene)}}


def _look(scene: Any) -> dict[str, Any]:  # WHY: bpy scene is untyped
    """The optional mood look (kit_export: ktrk_sky, ktrk_hills, ktrk_backdrop, ktrk_clock, ktrk_draw_r), only what the scene sets."""
    out: dict[str, Any] = {k: [int(c) for c in scene[f"ktrk_{k}"]] for k in ("sky", "hills", "clock") if f"ktrk_{k}" in scene}
    if "ktrk_backdrop" in scene:
        out["backdrop"] = str(scene["ktrk_backdrop"])
    if "ktrk_draw_r" in scene:
        out["draw_r"] = int(scene["ktrk_draw_r"])
    return out


def export_to(path: str, scene: Any = None) -> ktrk.Doc:  # WHY: bpy scene is untyped
    doc = kit_export.export(extract(scene or bpy.context.scene))
    Path(path).write_text(ktrk.dumps(doc))
    return doc


_METER: dict[str, Any] = {}  # WHY: the last meter reading (rows or an error), shown by the panel until the next refresh


def refresh(scene: Any) -> None:  # WHY: bpy scene is untyped
    try:
        doc = kit_export.export(extract(scene))
        _METER.update(rows=budget.rows(budget.meter(doc)), problems=budget.problems(doc), error="")
    except (kit_export.KitError, ValueError, KeyError) as e:
        _METER.update(rows=[], problems=[], error=str(e))


class KTRK_OT_export(bpy.types.Operator):
    """Write the scene as a .ktrk.json track"""

    bl_idname = "ktrk.export"
    bl_label = "Export .ktrk.json"
    filepath: bpy.props.StringProperty(subtype="FILE_PATH")  # type: ignore[valid-type]  # [valid-type] bpy property

    def execute(self, context: Any) -> set[str]:  # WHY: bpy context is untyped
        try:
            export_to(self.filepath, context.scene)
        except kit_export.KitError as e:
            self.report({"ERROR"}, str(e))
            return {"CANCELLED"}
        return {"FINISHED"}

    def invoke(self, context: Any, event: Any) -> set[str]:  # WHY: bpy types are untyped
        context.window_manager.fileselect_add(self)
        return {"RUNNING_MODAL"}


class KTRK_OT_meter(bpy.types.Operator):
    """Recount the track against the cart's limits"""

    bl_idname = "ktrk.meter"
    bl_label = "Refresh budget"

    def execute(self, context: Any) -> set[str]:  # WHY: bpy context is untyped
        refresh(context.scene)
        return {"FINISHED"}


class KTRK_PT_budget(bpy.types.Panel):
    bl_label = "Track Kit budget"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "Track Kit"

    def draw(self, context: Any) -> None:  # WHY: bpy context is untyped
        col = self.layout.column()
        col.operator("ktrk.meter", icon="FILE_REFRESH")  # it also refreshes itself after every edit (_live)
        if _METER.get("error"):
            col.alert = True
            col.label(text=_METER["error"], icon="ERROR")
        for label, value, limit, hard in _METER.get("rows", []):
            row = col.row()
            row.alert = value > limit  # red over budget
            row.label(text=f"{label}: {value} / {limit}{' (hard)' if hard else ''}")
        for p in _METER.get("problems", []):
            r = col.row()
            r.alert = True
            r.label(text=p)
        col.label(text=f"priced frame: trackc walk, ceiling {limits.FRAME_MC} Mc at R {limits.BENCH_R}")
        col.operator("ktrk.export", icon="EXPORT")


CLASSES = (KTRK_OT_export, KTRK_OT_meter, KTRK_PT_budget)


@bpy.app.handlers.persistent
def _live(scene: Any, depsgraph: Any) -> None:  # WHY: bpy types are untyped
    """The live meter: recount after every edit the depsgraph sees (an export of ~2 K vertices is a few ms)."""
    refresh(scene)
    from racer.blender import car

    car.refresh(scene)


def register() -> None:
    from racer.blender import car, moodpanel  # the Car Kit half (M5 step 3); the mood rows (M5 finish)

    for c in CLASSES:
        bpy.utils.register_class(c)
    moodpanel.register()
    car.register()
    bpy.app.handlers.depsgraph_update_post.append(_live)


def unregister() -> None:
    if _live in bpy.app.handlers.depsgraph_update_post:
        bpy.app.handlers.depsgraph_update_post.remove(_live)
    from racer.blender import car, moodpanel

    car.unregister()
    moodpanel.unregister()
    for c in reversed(CLASSES):
        bpy.utils.unregister_class(c)

