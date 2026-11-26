"""Track Kit limits (R82 M5): what the cart can hold (HARD, from its code) and what a track should cost (SOFT, our choice).

Both the converter's budget check (budget.py) and the Blender add-on's meter (blender/) read these, so the meter shows exactly
what the converter will refuse. docs/ports/kestrel_racing/M5.md explains each number.
"""

from __future__ import annotations

from typing import Final

# HARD: the cart refuses or breaks past these (u16 ids in the face records, the 32 x 32 world, seg.MAXSEG / minimap.MAXPTS,
# the palette: 16 + 30 ramps x 8 levels = 256 entries, ramps 12-14 the player's car and 15-18 the AI liveries)
MAX_VERTICES: Final = 65535
MAX_FACE_IDS: Final = 65535
MAX_SEGMENTS: Final = 256
FREE_RAMPS: Final = tuple(range(0, 12)) + tuple(range(19, 30))
CAR_RAMPS: Final = {"car_body": (12, (205, 35, 35)), "car_dark": (13, (45, 45, 55)), "car_glass": (14, (110, 150, 190))}
GRID_SLOTS: Final = 8

# SOFT: our budget for a track that holds 60 fps at the bench R (the stress city, 100 faces a tile, is the test that
# breaks it on purpose and is not checked). Faces count the inner faces (decals) too: they are drawn.
TILE_FACES: Final = 64
TRACK_FACES: Final = 3000
TRACK_VERTICES: Final = 8192
FRAME_MC: Final = 1.55  # the priced frame at the bench R (PORT_PLAN 3.4): under ~1.67 Mc = 60 Hz with a margin
BENCH_R: Final = 5

# The car (carc.py, R82 M5 step 3). HARD: the face record holds 3-4 vertices and u16 vertex ids; the cart draws exactly one
# shadow quad on the ground (carview.zig). SOFT: our budget, priced with frame_cost at the race grid (docs M5.md step 3).
CAR_MAX_VERTICES: Final = 65535
CAR_FACES: Final = 64  # the near model (LOD0: wheels + hull + cabin + wing)
CAR_VERTICES: Final = 128
CAR_LOD1_FACES: Final = 12  # the far model (a few pixels)
CAR_ENVELOPE: Final = ((-24, 24), (0, 32), (-40, 40))  # Q7, car space (x right, y up, z forward): the placeholder's + a margin
CAR_SHADOW_Y: Final = (0, 2)  # Q7 above the ground
