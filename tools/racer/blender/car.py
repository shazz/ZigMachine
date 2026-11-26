"""Kestrel Racing Car Kit: the add-on's car half (R82 M5 step 3, ours, MIT). Blender 5.3.

Exports the scene's `car_*` objects as the neutral `.kcar.json` (tools/racer/kcar_export.py has the conventions; carc.py makes
the cart's binary without Blender) and shows the car's budget in the sidebar's "Track Kit" tab, under the track's.
Registered by the add-on's register() (racer.blender).
"""

from pathlib import Path
from typing import Any

import bpy

from racer import carcheck, kcar_export, ktrk
from racer.kit_export import KitError

_METER: dict[str, Any] = {}  # WHY: the last car reading (rows or an error), shown by the panel until the next refresh


def extract(scene: Any) -> kcar_export.Scene:  # WHY: bpy scene is untyped
    from racer.blender import _mesh

    obs = sorted((o for o in scene.objects if o.type == "MESH" and o.name.startswith("car_")), key=lambda o: o.name)
    return {"objects": [_mesh(o) for o in obs],
            "scene": {"name": str(scene.get("kcar_name", scene.name)),
                      "sun": [float(c) for c in scene.get("kcar_sun", (0.35, 0.45, 1.0))]}}


def export_to(path: str, scene: Any = None) -> ktrk.Doc:  # WHY: bpy scene is untyped
    doc = kcar_export.export(extract(scene or bpy.context.scene))
    Path(path).write_text(ktrk.dumps(doc))
    return doc


def refresh(scene: Any) -> None:  # WHY: bpy scene is untyped
    try:
        doc = kcar_export.export(extract(scene))
        _METER.update(rows=carcheck.rows(doc), problems=carcheck.problems(doc), error="")
    except (KitError, ValueError, KeyError) as e:
        _METER.update(rows=[], problems=[], error=str(e))


class KCAR_OT_export(bpy.types.Operator):
    """Write the scene's car_* objects as a .kcar.json car"""

    bl_idname = "kcar.export"
    bl_label = "Export .kcar.json"
    filepath: bpy.props.StringProperty(subtype="FILE_PATH")  # type: ignore[valid-type]  # [valid-type] bpy property

    def execute(self, context: Any) -> set[str]:  # WHY: bpy context is untyped
        try:
            export_to(self.filepath, context.scene)
        except KitError as e:
            self.report({"ERROR"}, str(e))
            return {"CANCELLED"}
        return {"FINISHED"}

    def invoke(self, context: Any, event: Any) -> set[str]:  # WHY: bpy types are untyped
        context.window_manager.fileselect_add(self)
        return {"RUNNING_MODAL"}


class KCAR_OT_meter(bpy.types.Operator):
    """Recount the car against the cart's limits"""

    bl_idname = "kcar.meter"
    bl_label = "Refresh car budget"

    def execute(self, context: Any) -> set[str]:  # WHY: bpy context is untyped
        refresh(context.scene)
        return {"FINISHED"}


class KCAR_PT_budget(bpy.types.Panel):
    bl_label = "Car Kit budget"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "Track Kit"

    def draw(self, context: Any) -> None:  # WHY: bpy context is untyped
        col = self.layout.column()
        col.operator("kcar.meter", icon="FILE_REFRESH")
        if _METER.get("error"):
            col.alert = True
            col.label(text=_METER["error"], icon="ERROR")
        for label, value, limit, hard in _METER.get("rows", []):
            row = col.row()
            row.alert = value > limit
            row.label(text=f"{label}: {value} / {limit}{' (hard)' if hard else ''}")
        for p in _METER.get("problems", []):
            r = col.row()
            r.alert = True
            r.label(text=p)
        col.operator("kcar.export", icon="EXPORT")


CLASSES = (KCAR_OT_export, KCAR_OT_meter, KCAR_PT_budget)


def register() -> None:
    for c in CLASSES:
        bpy.utils.register_class(c)


def unregister() -> None:
    for c in reversed(CLASSES):
        bpy.utils.unregister_class(c)
