"""The Track Kit's scene properties as panel rows (R82 M5 finish), no bpy: what the add-on's "Track Kit mood" panel shows
and what its "Add mood properties" operator sets (tools/racer/blender/moodpanel.py).

The properties stay Blender custom properties on the scene (`ktrk_*`, the conventions in kit_export.py), so a scene made
before the panel, and every committed export, is unchanged; the panel only draws them as rows and fills in the missing
ones with the defaults below: what the export uses when a property is absent (the scene's name, a sun overhead, the oval's
look, the cart's computed clock), so adding them changes no converted track.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Final

from racer import mood


@dataclass(frozen=True)
class Prop:
    key: str  # the scene property (ktrk_<key>)
    label: str
    default: object
    hint: str  # what the value means (the row's tooltip line)


_M = mood.Mood()
PROPS: Final = (
    Prop("name", "Name", None, "the track's name (24 characters on the cart); unset: the scene's name, as the export"),
    Prop("mood", "Mood", "noon", "a name for the look"),
    Prop("sun", "Sun", (0.0, 0.0, 1.0), "the baked light's direction, Blender axes (Z up)"),
    Prop("far_ground", "Far ground", "", "the material the ground beyond the draw distance shows"),
    Prop("sky", "Sky top, horizon", [c for rgb in _M.sky for c in rgb], "2 x RGB: the copper's gradient"),
    Prop("hills", "Backdrop far, near, top", [c for rgb in _M.hills for c in rgb], "3 x RGB: the panorama strip"),
    Prop("backdrop", "Backdrop shape", mood.BACKDROPS[0], "one of " + ", ".join(mood.BACKDROPS)),
    Prop("clock", "Race clock start, extension", [0, 0], f"seconds; 0 = computed (max {mood.MAX_CLOCK[0]}, {mood.MAX_CLOCK[1]})"),
    Prop("draw_r", "Draw distance cap", 0, f"tiles {mood.R_MIN}..{mood.R_MAX}; 0 = none (the player's)"),
    Prop("haze", "Haze colour", [0, 0, 0], "RGB: what far faces blend toward (M6; usually the sky's horizon)"),
    Prop("haze_start", "Haze start", 0, "x/256 of the draw distance: nearer faces are untouched"),
    Prop("haze_strength", "Haze strength", 0, "x/255: the blend at the draw distance; 0 = no haze"),
)


def prop_name(p: Prop) -> str:
    return f"ktrk_{p.key}"


def missing(present: set[str]) -> list[Prop]:
    """The properties a scene with these custom properties does not have yet (the operator adds them)."""
    return [p for p in PROPS if prop_name(p) not in present]


def problem(p: Prop, value: object) -> str:
    """A row's value the converter would refuse ("" when fine): the panel shows it in red."""
    if p.key == "backdrop" and str(value) not in mood.BACKDROPS:
        return f"backdrop {value!r}: one of {', '.join(mood.BACKDROPS)}"
    if p.key == "draw_r":
        ok = isinstance(value, int) and (value == 0 or mood.R_MIN <= value <= mood.R_MAX)
        return "" if ok else f"draw_r {value!r}: 0 or {mood.R_MIN}..{mood.R_MAX}"
    if p.key in ("haze_start", "haze_strength"):
        return "" if isinstance(value, int) and 0 <= value <= 255 else f"{p.key} {value!r}: 0..255"
    n = {"sky": 6, "hills": 9, "clock": 2, "sun": 3, "haze": 3}.get(p.key)
    if n is None:
        return ""
    try:
        vals = [] if isinstance(value, str) else list(value)  # a list, a tuple or a bpy IDPropertyArray
    except TypeError:
        vals = []
    if len(vals) != n:
        return f"{p.key}: {n} numbers"
    if p.key == "clock" and not all(0 <= int(c) <= m for c, m in zip(vals, mood.MAX_CLOCK, strict=True)):
        return f"clock: start 0..{mood.MAX_CLOCK[0]}, extension 0..{mood.MAX_CLOCK[1]}"
    if p.key in ("sky", "hills", "haze") and not all(0 <= int(c) <= 255 for c in vals):
        return f"{p.key}: 0..255 each"
    return ""
