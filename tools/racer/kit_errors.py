"""The Track Kit's error table, track side (R82 M7): every message an author can meet, by the module that says it, and its
fix. `{}` stands for the part the message fills in. kit_errors_car.py has the car, panorama, pack builder and cart halves;
kit_manual.py writes both into docs/ports/kestrel_racing/TRACK_KIT.md; test_racer_kit_manual.py checks this table against
the messages in the code (kit_sites.py), both ways, so neither can drift.
"""

from __future__ import annotations

from typing import Final

TRACK: Final[dict[str, dict[str, str]]] = {
    "kit_export": {  # the export (the add-on's Export buttons and its live meter)
        "face {}: a DETAIL_FACE lies on no ground face":
            "a decal must lie flat on a TRACK_FACE or GROUND_FACE face (within 0.02 units of its edges): snap it onto the road",
        "face {}: the engine's normal disagrees with Blender's (winding)":
            "a scenery or wall face whose corners do not agree with its normal (bent or concave): flatten it or split it in triangles",
        "TRACK_L is not one closed edge loop ({} vertices without exactly two neighbours)":
            "TRACK_L must be one closed loop of edges round the track: every vertex in it joined to exactly two others in it",
        "LINE_START must hold exactly one TRACK_L vertex, and the start grid must exist":
            "put the start line's left vertex (and only it) in LINE_START, and parent the 8 grid empties to `start_grid`",
        "face {}: material {} has no ktrk_rgb":
            "give the material the custom property ktrk_rgb = [r, g, b] (0..255), or put the face on a material that has it",
        "TRACK_L vertex {}: {} TRACK_R vertices joined to it by an edge, want 1":
            "every left-edge vertex needs exactly one edge across the road to a TRACK_R vertex: the road is a strip of quads",
        "{} must hold exactly one TRACK_L vertex":
            "a CHECKPT_n group holds one left-edge vertex: the checkpoint is the segment ending there",
    },
    "ktrk": {"not a ktrk-json v1 document": "the file is not a Track Kit export: re-export it with the add-on"},
    "ktrk_check": {  # the validation (the converter's first stage)
        "{}: needs 3-4 valid vertex ids": "the cart draws triangles and quads only: triangulate or split n-gons",
        "{}: unknown kind {}": "a hand-edited document: a face kind is track, ground, wall or prop",
        "{}: ground normal does not point up": "a TRACK_FACE / GROUND_FACE face is upside down: flip its normal (Mesh > Normals > Flip)",
        "racing line needs at least 3 segments": "the TRACK_L / TRACK_R loops are too short: the line needs 3 segments or more",
        "racing line: vertex id out of range": "a hand-edited document: re-export it",
        "{}: not planar within {}": "a quad bends: flatten it, or split it into two triangles (banked roads change the bank slowly)",
        "{}: wound against the physics' inside test": "a drivable face must be convex seen from above (the physics' inside test): split it",
        "{}: more than 3 borders": "a ground face holds at most 3 BORDER edges: split the face",
        "checkpoint {} outside the line": "a hand-edited document: re-export it",
        "start grid is empty": "parent the 8 grid empties to an object named `start_grid`",
        "{} vertices outside the {}x{} tile world": "the world is 32 x 32 tiles of 8 units, centred on the origin: +-128 units in X and Y",
        "{}: border {} faces outward": "a BORDER edge must face into its face: check the face's winding",
        "face {} inner {}: not coplanar with its parent": "a decal must lie on its ground face's plane: snap it down",
        "face {} inner {}: outside its parent's edges": "a decal must sit inside ONE ground face: cut it where it crosses a face edge",
    },
    "budget": {  # the budget meter's refusals (the panel shows the same rows)
        "{} limit: {} {} > {}{}":
            "a meter row over its limit. HARD: the cart cannot hold it (merge materials, fewer segments). SOFT: over our frame "
            "budget (fewer faces in the busiest tile named, fewer faces or vertices)",
        "HARD limit: start grid has {} slots, the race needs {}": "parent exactly 8 empties to the `start_grid` object",
        "HARD limit: checkpoints {} must ascend strictly (the cart refuses the track at init)":
            "number CHECKPT_1..n in lap order from LINE_START, the last one at the start line",
        "HARD limit: face {}{} has no area (no normal)": "a face (or a decal) of zero area: merge its vertices away (Mesh > Clean Up)",
    },
    "kit": {  # the conversion (palette, mood, cues, the haze pool)
        "palette {}: want [r, g, b] ints 0..255, got {}": "ktrk_rgb must be three integers 0..255",
        "materials {} have no palette colour": "these materials are used by faces but have no ktrk_rgb",
        "far_ground {} is not in the palette":
            "ktrk_far_ground must name a material with ktrk_rgb. Blender drops a material no face uses when the file is saved: "
            "tick its Fake User (the shield) in the material list",
        "HARD limit: {} colour ramps > {}": "each material is a ramp: merge materials of close colours (23 at most, the far ground included)",
        "mood sun {}: want [x, y, z] with y > 0 (above the horizon)": "ktrk_sun is a direction with a positive Z in Blender (above)",
        "mood {} {}: want {} x [r, g, b] flattened ({} ints)": "ktrk_sky is 6 numbers (top, horizon), ktrk_hills 9 (far, near, top)",
        "mood backdrop {}: one of {}": "ktrk_backdrop is hills, docks or peaks",
        "mood clock {}: want [start, extension] in seconds (0 = computed)": "ktrk_clock is two integers, or [0, 0] for the computed clock",
        "mood draw_r {}: the draw distance cap in tiles (0 = none)": "ktrk_draw_r is an integer: 0, or 3..8",
        "mood world {} / car {}: Q8 ints {}..{}": "ktrk_world / ktrk_car are integers 64..4096 (256 = 1x)",
        "mood haze start {} / strength {}: ints 0..255 / 1..255": "ktrk_haze_start 0..255, ktrk_haze_strength 1..255 (0 = no haze)",
        "mood haze: {} face colours, the palette has {} spare entries (the cart's haze pool)":
            "the haze needs a spare palette entry per distinct face colour: fewer materials, or no haze",
        "an authored track needs {} (see tools/racer/kit.py)": "a hand-made document lacks palette, mood or far_ground: export it with the add-on",
    },
    "trackc": {  # the binary writer
        "material {} has no palette ramp": "a face's material is not in the palette: give it ktrk_rgb",
        "border edges {} must be ascending and inside the face": "a hand-edited document: re-export it",
        "racing line {}: cue {} is not 0..255": "a hand-edited document: the AI cues are baked by the converter",
        "mood ground ramp {} is past the palette's {} ramps": "a hand-edited document: re-export it",
    },
    "mood": {  # the mood block's own range checks (what the cart's trk.parse refuses as BadMood)
        "mood world {} / car {}: Q8 {}..{}": "ktrk_world / ktrk_car: 64..4096",
        "mood {}: level 0..7, backdrop < {}, flags {} only": "a hand-edited document: re-export it",
        "mood clock {}: start 0..{} s, extension 0..{} s": "ktrk_clock: a start of at most 250 s, an extension of at most 60 s",
        "mood draw distance cap {}: 0 (none) or {}..{} tiles": "ktrk_draw_r: 0, or 3..8",
        "mood colours {}, haze start {}, strength {}: ints 0..255": "every colour channel and haze number is 0..255",
        "mood haze {} start {} without a strength (0 = no haze)": "set ktrk_haze_strength, or clear ktrk_haze and ktrk_haze_start",
    },
    "mood_props": {  # the mood panel's red rows (the same checks before you export)
        "backdrop {}: one of {}": "hills, docks or peaks",
        "draw_r {}: 0 or {}..{}": "0 (none) or 3..8 tiles",
        "{} {}: {}..{} (Q8)": "the world / car scale: 64..4096, 256 = 1x",
        "{} {}: 0..255": "the haze start / strength: 0..255",
        "{}: {} numbers": "sky 6, hills 9, clock 2, sun 3, haze 3 numbers",
        "clock: start 0..{}, extension 0..{}": "start 0..250 s, extension 0..60 s",
        "{}: 0..255 each": "colour channels are 0..255",
    },
}
