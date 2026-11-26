"""Neon Docks (R82 M5 step 2): a container port at night, built as a Blender scene by this script and exported by the Track
Kit add-on. Original content (ours). The `.blend` is built at need, never committed; the export is.

    blender -b --factory-startup --python tools/racer/tracks/neon_docks_build.py -- tools/racer/tracks/neon_docks.ktrk.json
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import kit_scene  # noqa: E402
import neon_docks_geom as g  # noqa: E402
from salt_flats_geom import Mesh  # noqa: E402


def build() -> None:
    s = g.st()
    meshes = {k: Mesh() for k in ("track", "decals", "lamps", "shed", "yard", "cranes")}
    g.track(meshes["track"], s)
    g.decals(meshes["decals"], s)
    g.lamps(meshes["lamps"], s)
    g.shed(meshes["shed"], s)
    g.yard(meshes["yard"], s)
    g.cranes(meshes["cranes"])
    props = {"name": "neon_docks", "mood": "night", "sun": g.SUN, "far_ground": "ground", "sky": g.SKY, "hills": g.HILLS,
             "backdrop": "docks"}
    kit_scene.scene(props, g.PALETTE, g.DUAL, meshes)
    kit_scene.grid(s, [0.0] * g.N)


kit_scene.run("neon_docks", build)
