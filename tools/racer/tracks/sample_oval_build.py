"""Kestrel Oval (R82 M7), the Track Kit's sample track, built as a Blender scene by this script and exported by the add-on.
Original content (ours). The `.blend` is generated, never committed (add `--blend` to keep one: the manual's starting point);
the export is committed and the gate converts it to SAMPLE.KTR (docs/ports/kestrel_racing/TRACK_KIT.md).

    blender -b --factory-startup --python tools/racer/tracks/sample_oval_build.py -- tools/racer/tracks/sample_oval.ktrk.json [--blend sample_oval.blend]
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kit_scene  # noqa: E402
import sample_oval_geom as g  # noqa: E402
from salt_flats_geom import Mesh  # noqa: E402


def build() -> None:
    s = g.st()
    meshes = {k: Mesh() for k in ("track", "decals", "gantry", "scenery")}
    g.track(meshes["track"], s)
    g.decals(meshes["decals"], s)
    g.gantry(meshes["gantry"], s)
    g.scenery(meshes["scenery"], s)
    props = {"name": "kestrel_oval", "mood": "afternoon", "sun": g.SUN, "far_ground": "grass", "sky": g.SKY,
             "hills": g.HILLS, "backdrop": "hills", "haze": g.HAZE[0], "haze_start": g.HAZE[1], "haze_strength": g.HAZE[2],
             "clock": g.CLOCK, "draw_r": g.DRAW_R, "world": g.SCALE[0], "car": g.SCALE[1]}
    kit_scene.scene(props, g.PALETTE, g.DUAL, meshes)
    kit_scene.grid(s, [0.0] * g.N)


kit_scene.run("sample_oval", build)
