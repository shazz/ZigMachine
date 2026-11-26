"""Glacier Pass (R82 M5 step 2): an alpine road in snow, built as a Blender scene by this script and exported by the Track
Kit add-on. Original content (ours). The `.blend` is built at need, never committed; the export is.

    blender -b --factory-startup --python tools/racer/tracks/glacier_pass_build.py -- tools/racer/tracks/glacier_pass.ktrk.json
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import glacier_pass_geom as g  # noqa: E402
import kit_scene  # noqa: E402
from salt_flats_geom import Mesh  # noqa: E402


def build() -> None:
    s = g.st()
    meshes = {k: Mesh() for k in ("track", "decals", "tunnel", "scenery")}
    g.track(meshes["track"], s)
    g.decals(meshes["decals"], s)
    g.tunnel(meshes["tunnel"], s)
    g.scenery(meshes["scenery"], s)
    props = {"name": "glacier_pass", "mood": "overcast", "sun": g.SUN, "far_ground": "snow", "sky": g.SKY,
             "hills": g.HILLS, "backdrop": "peaks", "haze": g.HAZE[0], "haze_start": g.HAZE[1], "haze_strength": g.HAZE[2]}
    kit_scene.scene(props, g.PALETTE, g.DUAL, meshes)
    kit_scene.grid(s, g.heights()[0])


kit_scene.run("glacier_pass", build)
