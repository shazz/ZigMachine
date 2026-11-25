# Kestrel Racing: real Virtua Racing tracks for LOCAL benchmarking (`-Dracer_vr=true`)

Matt, 24 Nov: "locally we will need to use the real music and models to benchmark". The oval and the stress city are ours; the
KESTREL vs PEREGRINE numbers (R85's 3D-unit study) need a real game's geometry. freds72's PICO-8 data carts hold the three
tracks of the Mega Drive game, so this is a **local-only** path, in the spirit of `-Dracer_music`:

- **Nothing of the data is committed or shipped.** The importer and the cart code hold no track data; the decoded tracks live in
  the git-ignored `prototypes/racer_re/vr_local/` (and a copy in the git-ignored `apps/zig/assets/screens/racer_vr/`, ignored by
  `.gitignore`). A cart built with the option carries them: never commit it, never put it on a public card.
- **Without the option nothing changes**: the plain cart's wasm differs only by the track-set code; every gate harness and pin is
  as before (the `racer_headless` / `racer_drive` / `racer_race` pins are unchanged by this item).

## The pieces

| piece | what |
|---|---|
| `tools/racer/vr_cart.py` | reads a PICO-8 `.p8` data cart (gfx / map / flags / music / sfx sections = the 0x4300-byte memory image `reload` copies) and the engine's own `unpack_*` byte layout (`vracing_main.p8`: variants, doubles, faces with inner faces and border nibbles, segments, checkpoints), following the cart-to-cart stream. Plain Python (a re-implementation of the unpack functions, not freds72's code run under z8lua: the layout is 60 lines and the result is checked below) |
| `tools/racer/vr_import.py` | tracks 0-2 -> our `.ktrk.json` -> `trackc.convert(doc, mats, validate=False)` -> v3 binary, plus `vr_report.txt` (the budgets); `python3 -I tools/racer/vr_import.py` |
| `racer/vr.zig`, `racer/trackset.zig` | the build option, the three blobs (comptime-embedded only with the option), the track set, binding driving / race / minimap to the track on show |
| `Race.pilot` / `Game.pilot` | on a VR track the player is flown by the AI's PID controller (`npc.control`), because the recorded button streams are the oval's; lap v2 (`x`) therefore runs on any track |
| `apps/harness/racer_vr_costs.mjs` | the frame-cost estimates on the VR tracks (needs a VR cart; not in the gate) |
| `prototypes/cards/racer_vr_bench.mjs`, `build_racer_vr.sh` | local (git-ignored): the node counter run, and the card build + stage recipe |

**Decoding checks.** The three tracks decode to coherent geometry: coordinates inside +-100 units (the 32 x 32 tile world is +-128),
every face and segment index in range, 121 / 166 / 166 racing-line segments, 3 checkpoints each (his are 1-based Lua indices, the last is
the segment count: stored -1), start positions on the racing line (within 1-4 units of segment 0-3). The flags layout is the one our
converter's was designed on (bit 0 dual, 1 quad, 3 inner faces, 4 ground, 5-7 border count; bit 2 = NOT asphalt, inverted on import).
Three tracks, not twelve: `vracing_1..12.p8` are the data's overflow carts (the track directory in cart 0 holds 3 entries).

## Keys (a `-Dracer_vr` cart)

`t` cycles oval, VR1, VR2, VR3 (**the city is dropped in this cart**: see the RAM window below); `l` the flyby (lap v0) on the track shown;
`x` lap v2 (the race, 8 cars, the player on the pilot) pinned at R = 5 like the oval's; `n` / `e` drive / race by hand; `3`-`8` the draw
distance (default 8); `o` the OSD; the per-stage counters print on the console like the oval's (`racer,csv,...`, `racer,lap,...` with
the track name `VR1`..`VR3`). `b` (lap v1) is the oval's (its stream) and moves back to the oval.

## Budgets: what the real tracks need against the cart

| | oval (ours) | VR1 | VR2 | VR3 | cart limit |
|---|---|---|---|---|---|
| vertices | 1,301 | 5,304 | 4,389 | 5,729 | u16 ids, vertex cache sized to the largest |
| faces (+ decals) | 600 (+301) | 2,249 (+552) | 2,743 (+551) | 2,521 (+699) | u16 ids |
| racing-line segments | 120 | 121 | 166 | 166 | `seg.MAXSEG` 256 |
| tiles used of 1,024 | | 213 | 260 | 183 | |
| busiest tile (faces) | | 59 | 60 | 103 | |
| distinct colours -> ramps | 12 ramps | 28 -> 23 | 28 -> 23 | 26 -> 22 | 23 free ramps (0-11, 19-29) |
| binary | 241 KB | 409 KB | 497 KB | 389 KB | |

- **The RAM window is the budget that bites.** The cart's image and its buffers share the 2 MiB window (`zg.mem`): the plain cart has
  546 KB free with the oval + city blobs (241 + 755 KB). The three VR tracks (1.29 MB) do not fit beside the city: the first
  VR build died at init with the arena full (`zg.mem: cart RAM window full`). **A VR cart therefore drops the city** (and the
  city's larger vertex / face buffers): free RAM is **514 KB** with oval + VR1-3. A fourth track of this size would not fit.
- Polygons a frame stay far under `MAXP` = 6,144 (at most 691 in the lap v2 runs, R = 5 and R = 8 flybys 536). `R_BAKE` = 8 covers R = 8.
- **Cut, and said so:** 7 zero-area faces of VR1 are dropped by the importer (it reports them in `vr_report.txt`); decals that are
  degenerate likewise. The merged colours (5 on VR1 and VR2, 4 on VR3 of 26-28) take their nearest ramp. Per-face dither pairs
  (his fill patterns) become the average RGB of the pair. **Not imported:** his sky colour (ours is the oval's gradient), his car
  models (decoded by `vr_cart.read_models`: `car` 83 vertices / 24 faces, `car_ai` 81 / 30, three LODs each, but not wired into the
  car-face records; the racer's own boxes are drawn), the original's start line (the grid is synthesised on segments 0-4 like the oval's:
  the player behind, the AI cars two a row) and his lap scoring. The physics runs on his faces with our (bit-exact) port of his
  ground / border code, never run against his track in the Lua reference: **no bit-exactness claim exists on these tracks**, only
  that the pilot drives the grid (`racer,cars` CRC lines are printed for a later reference run if wanted).

## Counters (node, no board: `racer_vr_bench.mjs <worktree> <1|2|3> x`, R = 5, CPU fill, per 32-frame window over lap v2's round)

| lap v2 | tiles | faces | verts | polys | spans | pixels |
|---|---|---|---|---|---|---|
| oval | 15 (max 19) | 73 (87) | 151 (222) | 141 (244) | 716 (1,081) | 35.8 k (49.0 k) |
| VR1 | 24 (33) | 318 (486) | 680 (930) | 380 (473) | 2,357 (4,297) | 51.5 k (80.3 k) |
| VR2 | 26 (32) | 345 (472) | 537 (806) | 378 (517) | 2,163 (2,908) | 44.7 k (55.3 k) |
| VR3 | 20 (29) | 347 (644) | 697 (1,313) | 404 (691) | 2,265 (3,654) | 40.5 k (79.7 k) |

Faces to collect are 4-5x, vertices to transform 3.5-4.5x, polygons ~2.7x, edge-walked spans ~3x, painted pixels 1.1-1.4x the
oval's. The per-stage microseconds (`vis / collect / sort / sky / fill / hud`) are 0 in node: the board fills them
(`racer,csv` over serial; the OSD `o`). Those counters, per stage, are what the PEREGRINE 3D-unit study ranks on:
**transform + collect** (faces, vertices) grow ~4x; **fill** (spans, pixels) only ~1.2-3x.

## Frame-cost estimate (`racer_vr_costs.mjs`, plain multiply twin, CPU fill; 1.67 Mc is a 60 Hz frame)

| scene | VR1 | VR2 | VR3 |
|---|---|---|---|
| heaviest flyby pose, R = 5 | 2.24 Mc (~45 fps) | 2.14 (~47) | 2.19 (~46) |
| the same, R = 8 | 2.59 (~39) | 2.55 (~39) | 3.24 (~31) |
| lap v2, start grid, R = 5 | 3.80 (~26) | 4.11 (~24) | 3.20 (~31) |
| lap v2, mid-lap, R = 5 | 5.49 (~18, max 8.4) | 4.67 (~21) | 5.26 (~19) |

The AFFINE fill is within 4 % of the CPU fill everywhere. **How far to trust it:** the same model said 3.06 Mc (~33 fps) for the oval's
mid-lap lap v2 and the board ran it at **60 fps** (M3.md, board results): its instruction-cache term is far too pessimistic, by about 2x
on this cart. Halving the VR figures gives ~2.2-2.7 Mc mid-lap, i.e. **somewhere around 40-45 fps expected on KESTREL** at R = 5
on the real tracks (fewer at R = 8, and the busiest frames worse): the board decides, and this is the first real "does a PEREGRINE 3D unit
matter" measurement. (The mid-lap frame in this model also pays the AI tick: 7 cars + the pilot's controller.)

## Building the card

`/home/matt/projects/ZigMachine/prototypes/cards/build_racer_vr.sh <tag> <rev>` (like `build_racer_version.sh`: a scratch worktree at
`<rev>`, the importer run, the three `.ktrk` copied into the worktree, `zig build -Dracer_vr=true`, `make split-cart CART=racer`, `card.py stage`
for system 1.28; under the build lock; the worktree is removed). The staged card is a `RACER VR` entry: board to-do, in this order:
(1) `x` on VR1, VR2, VR3: fps and the `racer,csv` stage lines on the serial console; (2) the same at `u` (uncapped) for the cart-only rate;
(3) `e` and drive by hand on one track (the car on his asphalt / walls: does the physics keep the car on the road, do the borders behave);
(4) the OSD plane cost with 4 planes enabled as ever.
