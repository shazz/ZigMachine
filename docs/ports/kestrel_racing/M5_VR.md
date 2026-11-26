# Kestrel Racing: real Virtua Racing tracks for LOCAL benchmarking

> **Since M5 step 2 (25 Nov) the tracks are disk FILES, and `-Dracer_vr` is gone** (M5.md, "Tracks off the disk"). The cart is
> the same for everyone; a LOCAL disk carries the VR tracks: `RACER_EXTRA="VR1.KTR=<vr_1.ktrk> VR2.KTR=... VR3.KTR=..."
> tools/mkdisks.sh` adds them after the shelf's tracks (ZX0-packed like those), and `prototypes/cards/build_racer_vr_disk.sh` (new; the old `build_racer_vr.sh` is the `-Dracer_vr` recipe and fails on later revisions) does
> it in its scratch worktree. **Nothing is committed and the shelf disk never holds them.** The importer now writes each
> track's mood block (far ground at level 7, his unlit `rectfill`), so the cart no longer knows a VR track by its index. The
> city is no longer dropped: only one track is in RAM at a time. `t` walks OVAL, CITY, SALT, NEON, GLACIER, VR1, VR2, VR3
> on such a disk; `racer_vr_costs.mjs --tracks 5,6,7` with `RACER_ZMD=<the local disk>` prices them. The sections below
> are the history of the `-Dracer_vr` cart (its keys, its RAM window) and stay as measured then.

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
converter's was designed on (bit 0 dual, 1 quad, 3 inner faces, 4 ground, 5-7 border count; bit 2 = asphalt: set on the road's grey faces; his engine caps the rpm and shakes the camera when it is clear. The first import had it inverted, 25 Nov fix).
Three tracks, not twelve: `vracing_1..12.p8` are the data's overflow carts (the track directory in cart 0 holds 3 entries).

## Keys (a `-Dracer_vr` cart)

`t` cycles oval, VR1, VR2, VR3 (**the city is dropped in this cart**: see the RAM window below); `l` the flyby (lap v0) on the track shown;
`x` lap v2 (the race, 8 cars, the player on the pilot) pinned at R = 5 like the oval's; `n` / `e` drive / race by hand; `3`-`8` the draw
distance (default 8); `o` the OSD; the per-stage counters print on the console like the oval's (`racer,csv,...`, `racer,lap,...` with
the track name `VR1`..`VR3`). `b` (lap v1) is the oval's (its stream) and moves back to the oval. `i` cycles the VR tracks' debug
shading (below): FLAT (the default) / LIT / SOFT, shown after the track name on the HUD (`VR1/LIT`) and printed as `racer,shade,<mode>`;
it changes nothing on the oval.

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
  degenerate likewise. Colours: see the next section. **Not imported:** his sky colour (ours is the oval's gradient), his car
  models (decoded by `vr_cart.read_models`: `car` 83 vertices / 24 faces, `car_ai` 81 / 30, three LODs each, but not wired into the
  car-face records; the racer's own boxes are drawn), the original's start line (the grid is synthesised on segments 0-4 like the oval's:
  the player behind, the AI cars two a row) and his lap scoring. The physics runs on his faces with our (bit-exact) port of his
  ground / border code, never run against his track in the Lua reference: **no bit-exactness claim exists on these tracks**, only
  that the pilot drives the grid (`racer,cars` CRC lines are printed for a later reference run if wanted).

## Colours: solid, unlit, arcade tones (25 Nov, `tools/racer/vr_colours.py`)

Matt on the board (25 Nov): the VR tracks were "way brighter" than the original, and the faces the models alternate on purpose
(the road's grey / dark grey panels, the mountains' close tones) were far too different. The target is the ARCADE look: solid
colours, no dither, mid-tone, low contrast between the alternating faces. What the first import did wrong, measured:

1. **Two palette entries decoded wrong.** His `_init` remaps PICO-8 colours 14 and 15 to the secret palette (`pal(14,128,1)`,
   `pal(15,131,1)`: dark brown #291814, dark teal #125359; his exporter's Genesis table says the same). We used the default pink
   #FF77A8 and peach #FFCCAA: every face with a 14 / 15 nibble (trees, rock, ~10 % of the faces) came out far too bright
   (byte `ff`: luma 64 in his palette, 115-212 in ours).
2. **Lighting on top of pre-shaded colours.** His engine draws every face unlit (`polyfill(d, d.c)`: the relief is baked into the
   neighbouring faces' colours by Sega's artists). Our converter lit each face by its normal (36-99 %), so one colour byte spread
   over up to ~90 luma (road `66`: 105-192) and two faces of the SAME byte differed by up to 22 luma.
3. **His palette is not the arcade.** PICO-8's 16 colours are a coarse stand-in for the Mega Drive's: his exporter folds Genesis
   "7" and "8" into 6 and puts the road's darker panel ("9") on 13, so his road alternates luma 195 / 160 / 126 (bytes `66` / `6d` / `dd`).
   Matt's arcade screenshots: road panels ~90-116 grey, about 10-25 apart.

The importer now gives each face ONE solid colour: the average of its dither pair (his fill pattern `0xa5a5` is a 50 % checkerboard,
so the average is what it reads as), each nibble taken through a tone table, unlit (palette level 7 = the stored RGB; the far
ground too, as his `rectfill`). `TONES = "ARCADE"` (default) is **our calibration, not ripped data**: per PICO-8 index, the tone of
the same surface sampled from two arcade screenshots (road panels 112 / 92 grey, grass greens, dark trees), the banks and rock
(indices 4 and 9: one PICO-8 index stands for two Genesis colours there) kept in his luma ORDER and spacing, darker; `TONES = "PICO"`
is his palette decoded right, to compare. A track with more colour bytes than the 23 free ramps puts the rest on the nearest
(ramp, level) shade (`vr_report.txt` lists them and the error: 2-4 rarely used bytes a track).

Measured over every pair of edge-adjacent faces (props included) with different colour bytes, |luma difference|, median:

| | his PICO-8 | before | after |
|---|---|---|---|
| road panel on road panel (`66`/`6d`/`dd`), every track | 35 | 31 | 10 |
| VR1 banks `44`/`49` (337 pairs), `49`/`99` | 33, 34 | | 22, 22 |
| grass bands `33`/`3b`, `3b`/`bb` | 25, 26 | | 18, 18 |
| any pair, VR1 / VR2 / VR3 | 33 / 42 / 53 | 30 / 34 / 37 | 21 / 31 / 31 |
| two faces of the SAME byte, max | 0 | 18-22 | 0 |
| face-weighted mean luma, VR1 / VR2 / VR3 | 134 / 161 / 154 | 116 / 146 / 127 | 97 / 113 / 103 |

Every alternation is now closer than in his palette; the pairs that grow are boundaries, not alternations (the light verge `77`
beside the now mid-grey road: 49 -> 88, as the arcade's ~200 verge beside its ~90 road). Arcade samples for reference: road
107 / 116 (Big Forest), 90 / 66 (Acropolis), verge 198-202, grass (76,138,0) and darker (34,90,1), trees (0,49,2), sky (0,49,247).

**Debug key `i`** (Matt wants to compare on the board): the import stores two more shades per face in the record's last word
(`trk.Face.alt`, 0 on every committed track and the cars, so nothing else changes): FLAT (default) = the colour as stored; LIT = the
converter's light by the normal, the old look on the new tones; SOFT = a gentle light (levels 5-7). The far ground follows
(level 7 in FLAT, 4 otherwise).

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
