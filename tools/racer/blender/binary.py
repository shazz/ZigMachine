"""Kestrel Racing Track Kit: the cart's binaries straight from Blender (R82 M7). Blender 5.3.

The packaged add-on carries the converters (tools/racer/kit.py for a track, carc.py for a car; pure Python), so an author
without the repository writes the files the cart loads: `NAME.KTR` (a track: C:\\RACER\\ or a track pack disk) and
`NAME.KCR` (a car: `<TRACK>.KCR` for one track, `CAR.KCR` for every track). The same budget check and refusals as the
command-line converters, reported in Blender's status bar. Registered by the add-on's register() (racer.blender).
"""

from pathlib import Path
from typing import Any

import bpy

from racer import carc, kcar_export, kit, kit_export, trackc
from racer.kit_export import KitError


def track_bytes(scene: Any) -> bytes:  # WHY: bpy scene is untyped
    from racer.blender import extract

    return kit.convert(kit_export.export(extract(scene)))


def car_bytes(scene: Any, scale: float) -> bytes:  # WHY: bpy scene is untyped
    from racer.blender import car

    return carc.convert(kcar_export.export(car.extract(scene)), scale=scale)


def _write(op: Any, make: Any) -> set[str]:  # WHY: a bpy operator and a callable over the scene
    try:
        Path(op.filepath).write_bytes(make())
    except (KitError, trackc.ConvertError, carc.CarError, ValueError) as e:
        op.report({"ERROR"}, str(e))
        return {"CANCELLED"}
    return {"FINISHED"}


class KTRK_OT_export_ktr(bpy.types.Operator):
    """Convert the scene to the cart's track file (.KTR: put it in C:\\RACER\\ or on a track pack disk)"""

    bl_idname = "ktrk.export_ktr"
    bl_label = "Export .KTR (cart)"
    filepath: bpy.props.StringProperty(subtype="FILE_PATH")  # type: ignore[valid-type]  # [valid-type] bpy property

    def execute(self, context: Any) -> set[str]:  # WHY: bpy context is untyped
        return _write(self, lambda: track_bytes(context.scene))

    def invoke(self, context: Any, event: Any) -> set[str]:  # WHY: bpy types are untyped
        context.window_manager.fileselect_add(self)
        return {"RUNNING_MODAL"}


class KCAR_OT_export_kcr(bpy.types.Operator):
    """Convert the scene's car_* objects to the cart's car file (.KCR: <TRACK>.KCR or CAR.KCR)"""

    bl_idname = "kcar.export_kcr"
    bl_label = "Export .KCR (cart)"
    filepath: bpy.props.StringProperty(subtype="FILE_PATH")  # type: ignore[valid-type]  # [valid-type] bpy property
    scale: bpy.props.FloatProperty(name="Scale", default=1.0, min=0.25, max=8.0)  # type: ignore[valid-type]  # [valid-type] bpy property

    def execute(self, context: Any) -> set[str]:  # WHY: bpy context is untyped
        return _write(self, lambda: car_bytes(context.scene, self.scale))

    def invoke(self, context: Any, event: Any) -> set[str]:  # WHY: bpy types are untyped
        context.window_manager.fileselect_add(self)
        return {"RUNNING_MODAL"}


CLASSES = (KTRK_OT_export_ktr, KCAR_OT_export_kcr)


def register() -> None:
    for c in CLASSES:
        bpy.utils.register_class(c)


def unregister() -> None:
    for c in reversed(CLASSES):
        bpy.utils.unregister_class(c)
