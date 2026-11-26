"""Kestrel Racing Track Kit: the scene's mood properties as panel rows (R82 M5 finish, ours, MIT). Blender 5.3.

The "Track Kit mood" panel (3D view sidebar, "Track Kit" tab, under the budget) draws each `ktrk_*` scene property as an
editable row (they stay custom properties: tools/racer/mood_props.py has the list, the defaults and the checks), a value
the converter would refuse in red, and an "Add mood properties" button that sets the missing ones to their defaults
(never overwriting one that is set). Registered by the add-on's register() (racer.blender).
"""

from typing import Any

import bpy

from racer import mood_props


class KTRK_OT_mood_defaults(bpy.types.Operator):
    """Add the mood properties this scene does not have yet, at their defaults"""

    bl_idname = "ktrk.mood_defaults"
    bl_label = "Add mood properties"

    def execute(self, context: Any) -> set[str]:  # WHY: bpy context is untyped
        add_missing(context.scene)
        return {"FINISHED"}


def add_missing(scene: Any) -> list[str]:  # WHY: bpy scene is untyped
    """Sets every missing ktrk_* property to its default; returns the keys it added."""
    added = []
    for p in mood_props.missing(set(scene.keys())):
        scene[mood_props.prop_name(p)] = scene.name if p.default is None else p.default  # name: the scene's, as the export
        added.append(p.key)
    return added


class KTRK_PT_mood(bpy.types.Panel):
    bl_label = "Track Kit mood"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "Track Kit"

    def draw(self, context: Any) -> None:  # WHY: bpy context is untyped
        scene, col = context.scene, self.layout.column()
        for p in mood_props.PROPS:
            name = mood_props.prop_name(p)
            if name not in scene:
                col.label(text=f"{p.label}: not set (default {p.default})")
                continue
            row = col.row()
            bad = mood_props.problem(p, scene[name])
            row.alert = bool(bad)
            row.prop(scene, f'["{name}"]', text=p.label)
            if bad:
                col.label(text=bad, icon="ERROR")
        if mood_props.missing(set(scene.keys())):
            col.operator("ktrk.mood_defaults", icon="ADD")


CLASSES = (KTRK_OT_mood_defaults, KTRK_PT_mood)


def register() -> None:
    for c in CLASSES:
        bpy.utils.register_class(c)


def unregister() -> None:
    for c in reversed(CLASSES):
        bpy.utils.unregister_class(c)
