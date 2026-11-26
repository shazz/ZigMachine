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

## Virtua Racing Deluxe (32X): the five courses from Matt's own cartridge (25 Nov, LOCAL ONLY)

Matt owns the cartridge and dumped it himself; the dump stays git-ignored in `prototypes/racer_re/vr_local/32x/`, and so does
everything decoded from it (`vr32x_<n>.ktrk.json`, `vr32x_<n>.ktrk`, `vr32x_report.txt`). The same rule as above: the committed
importer is LOGIC only (no geometry, colours, tables, or offsets of data; the two tables it needs are FOUND by scanning for their
shape), nothing derived is committed or put on a shared card. Deluxe has the arcade three plus Highland and Sand Park; all five go
through the same code. `python3 -I tools/racer/vr32x_import.py --allow-soft` (default paths), `--tracks 4,5` for a subset.

| piece | what |
|---|---|
| `tools/racer/vr32x_rom.py` | the decoder. Per course a 32 x 32 map of tile-model pointers (SH-2 ROM addresses, a 4 KB block found by its shape); a tile model is its vertices (s16 x, y up, z; 2048 to a tile) and polygons in STRIPS (flags bit 0 triangle / quad; a high byte of 2, 4 or 6 reuses edge last / 2 / 1 of the previous polygon); the colour word's high byte is a palette index into the course's 256-entry 32X palette (5-bit RGB), found as a run of five pointers 512 bytes apart. freds72's `32x_dumper.py` only probed the layout; the 68000's tile lookup is described by the sega-vr-disasm project |
| `tools/racer/vr32x_geom.py` | one welded mesh (1/256 of a model unit = our unit, as his Genesis export), kinds (up-facing = ground, neutral grey = asphalt incl. kerbs to ny 0.3, the rest props; flags bit 6 = dual-sided, a guess from the Genesis layout), decals (a ground face lying in a larger one becomes its `inner`), borders (a ground edge past which no ground continues at the same height) |
| `tools/racer/vr32x_line.py`, `vr32x_walk.py`, `vr32x_cells.py` | the SYNTHESISED racing line, now the fallback behind `--synth` (the 32X's own course tables are decoded since 26 Nov: see below): candidates are the shortest lap through a cut across the road at seeds spread over the asphalt (a 0.25-unit cell graph of the asphalt, heights kept apart so an overpass does not join the road below) and a walk that follows the road (it takes a lollipop the shortest lap skips: Acropolis' hook); the longest that does not double back wins, smoothed, resampled every ~3.5 units, edges as new vertices |
| `tools/racer/vr32x_tables.py`, `vr32x_find.py`, `vr32x_surface.py` | the 68000's course tables (26 Nov, the default): the course table (path, course-index map, respawn pairs, AI lines), the surface map (per course a map of polygon lists, plus the upper deck of a crossing) and the start grid, each FOUND by its shape and accepted only when it agrees with the others (no offsets in the code) |
| `tools/racer/vr32x_course.py`, `vr32x_kinds.py`, `vr32x_decoded.py` | what we build from them: the racing line on the 32X's own points, the checkpoints from its timing gates, the grid from its poses, each ground face's kind from the surface under it (walls = the edge of the drivable union), and a fail-loud check that the decode and our mesh agree |
| `tools/racer/vr32x_colours.py` | colours: each face its palette entry, solid and unlit (no dither); the entries (74-99 a course) go on the 23 free ramps: the road and the far ground first, then greedily the entry worst served, weighted by area, the rest on the nearest ramp shade (`vr32x_report.txt` gives the error: ~4-5 RGB area-weighted, a few rare entries 50-180 off) |
| `tools/racer/vr32x_import.py` | the pipeline and the report: decoded mode by default (the course tables below; a table not found is an error, never a silent fallback), `--synth` for the old synthesis (checkpoints a third of the lap apart, vr_import's grid on segments 0-4, forced clockwise), the budget check (SOFT overruns refused unless `--allow-soft`), trackc v3 + a mood block (far ground at level 7) |
| `tools/tests/test_racer_vr32x.py` | synthetic models (strip edges, bad ids, no table) and a synthetic ring for the lap; no Sega data, runs in the gate |
| `tools/tests/test_racer_vr32x_course.py` | a synthetic cartridge in the decoded layout (a ring course, one road polygon per point, a grid): the tables found by shape, the bank, a missing table refused, the edge and gate bits, the layer switch, checkpoints and a missing gate refused, face kinds; no Sega data |

**What decoded, what did not.** All five courses' tile maps and every model parse with every vertex id in range, the models
contiguous; the strip rule gives convex, edge-sharing polygons for 85-99 % of the continuations (the rest are folds of the
terrain). Laps (the delivered, smoothed line): Big Forest 438 units (freds72's Genesis track: 437), Bay Bridge 432 (422),
Acropolis 547 (556, the hook included): within 0.2-2.4 % of his, so the geometry is the same circuit at the same scale and
orientation (Big Forest overlays his VR1 without a mirror; his VR2 has the shape of map 2, Acropolis, and his VR3 of map 1,
Bay Bridge). Highland (a figure-8, the crossing is a bridge) 433, Sand Park (the longest, as reviews say) 661. **Synthesised in the first import (25 Nov), decoded since 26 Nov (below):** the racing line, checkpoints, start grid and its
place, the driving direction, the borders and the face kinds. **Unknown and unused:** the model header's second word, the colour word's low byte, flags bits 1-6 (bit 6 used as dual).
The maps are in the 68000's track order; the two Deluxe courses are Highland and Sand Park (a desert course, the
longest: map 4 is sand-coloured and the longest lap).

**The course data, decoded (26 Nov, branch feat/racer-32x-data).** Read from the 68000 code with rg-dis (Reservoir Gods'
disassembler, the 68000 window of the dump as a raw image) and the sega-vr-disasm project's labels as an index (its notes were
wrong in places: the course and the car class are swapped in its names, the "palette" copy is the settings block). What the
68000 does, and what we take:

- **Course index and direction.** A car's course index comes from the surface polygon under it (each polygon names a path
  point; a byte map turns the point into the index). The lap check counts a lap when the index drops by more than 100, so the
  driving direction is increasing index and the start/finish line is where index 0's region starts. Our racing line keeps the
  32X's points one to one (a segment per course index, boundaries at the midpoints between points, rotated by one so the line
  is the start of the last segment: the race rules' gates then fall exactly on the 32X's). The pit lane's extra points (mapped
  back onto the main indices) are not part of the line.
- **Checkpoints.** The surface byte's top two bits are a timing gate (1 at index 0, 2 and 3 the split points, read by the
  split-time display); our checkpoints are gates 2 and 3, then the line.
- **The grid.** 16 poses per course and car class (x, height, z, heading), the player first and AT THE BACK; we keep the player
  and the 7 cars just ahead. The height word is copied between courses and every heading is straight ahead, so height comes
  from our ground and yaw from the line. A car behind the line starts at segment 0 and the track position walks it back on the
  first tick (its u starts below 0, the first lap is a whole one, as on the 32X).
- **Walls and surfaces.** The 32X stores no walls: a 512-unit cell holds convex polygons (four half-plane edges, a height
  plane, a class, flags), a probe in no polygon is solid, so a wall is the edge of the polygons' union. Classes: road (and
  kerb, pits), three off-road classes (each slows the car), solid. One course has a second map, the upper deck of its
  crossing, selected by a flag of the polygon the car is on. We kind each ground face by sampling the surface under it
  (road -> track, off-road -> ground, solid / none / a face not on the surface's plane, e.g. a rock or a deck over the road ->
  not drivable), and the existing border rule then puts the walls where the drivable union ends.
- **Units.** The 68000's x / z are half a model unit (128 to one of ours); its plane heights are 2048 to one of ours. Checked:
  every path point lands on a polygon of its own course index (both layers walked), every path point and grid car lies on our
  asphalt.

Checks (node, local disk, the pilot flying the player through a 3-lap race, `prototypes/cards/racer_32x_race.mjs`): laps within
0.5 % of freds72's for the three shared tracks (the synthesised ones were 2-5 % long), the grid on each course's real start
line (on Big Forest the grid stands well past the line, as on the 32X), no car stuck on a wall or off the road on four
courses (the synthesis had cars stuck for most of the race on three); **Highland's crossing** still traps a car or two: our
`find_face` is x/z only (freds72's tracks have no overpass), so a car crossing under the deck can be snapped onto it. That is an
engine limit, not the data's. The pilot times out on every course: freds72's clock (75 s + 10 s a checkpoint, 3 checkpoints
here) is too short for these laps; the 32X's own time extends are not decoded.

**Physics and AI against the 32X (26 Nov; a reading of the 68000 code, nothing changed in the cart).** Our physics is freds72's
Lua bit for bit (M2.md) and stays so; this is what a "32X feel" would mean, as OUR OWN tuning measured against it:

- **Rate and scale.** The 68000 runs one physics step per rendered frame (its loop waits for the SH-2's "frame done"; the
  disasm project measures ~20 fps), our tick is a fixed 30 Hz. Its speedometer is a fixed multiple of its speed word, and a frame
  moves the car by a sixteenth of that word in world units, so at its nominal 20 fps its km/h maps onto our world within a few % of
  freds72's own `* 900` (the world scales were already the same, see Speed feel in M2.md). Its car really drives slower
  than the speedometer when the frame rate drops; ours does not.
- **Longitudinal.** The 32X has an engine model: a torque curve over rpm, a 7-speed box (automatic or manual) with shift
  points, a speed-dependent drag curve per car class, throttle and brake that ramp in, a wheelspin grip limit, and three
  car classes. A full-throttle reading of it (local script) gives about our top speed for the Formula class but a slower
  pull in the upper gears (we reach the top end noticeably sooner). Off-road it adds drag growing with the square of speed
  (halved with one or two wheels off), where ours caps the engine at 2/3 of its top speed.
- **Walls.** The 32X probes four car corners against the surface map; a corner in no polygon is a wall hit: the step is
  rolled back to the last free quarter-step (no push-out), the car is turned onto the course heading stored in the polygon,
  and a hard hit at speed is a crash that respawns the car on the path. Ours pushes the car out of the wall edge and scales
  the velocity by the contact (freds72's `face_collide`).
- **AI.** The 32X's AI cars are kinematic: each follows one of four authored lines per course (a point per course index with a
  speed cue: negative before the corners), aims two points ahead, turns by a fraction of the heading error that grows as
  the point nears, and moves at a target speed = its base speed + a per-group cornering factor x the cue. They do not run
  the player's tyre model. Ours (freds72's) run the full car physics with a PID on the racing line. Rubber-banding was
  not confirmed in the code read.

**How we would match it (a proposal, nothing built).** (1) Speed feel: fit our own torque / drag CURVES (a few control
points, our numbers, not the 32X's tables) so the 0-100 / 0-200 / top-speed times and the off-road loss land near the 32X's
measured behaviour, behind a per-car-class parameter block in the track or car file. (2) AI: optional authored speed cues
per segment (our Track Kit could bake them from a fast lap) feeding the existing PID's target speed. (3) Walls: keep the
push-out (it is the Lua's). Cost: every such change breaks the bit-for-bit Lua oracle (the M2/M3 pins), so it needs either
the same change made in the Lua harness (the oracle follows us) or a new oracle = our Zig model re-pinned, plus new race /
lap pins; a few days. Copying the 32X's torque, drag, gear or AI tables verbatim would put Sega data in the shipped cart:
not allowed; fitted curves of our own are.

**Budgets.** Every course is over the SOFT budget (a local benchmark, so `--allow-soft`): ~5,100-6,500 faces drawn with their
decals (soft 3,000), a busiest tile of 119-165 faces (soft 64), up to ~9,200 vertices (soft 8,192: three courses). The HARD limits
hold (23 ramps, <= 256 segments, ids). Binaries 0.50-0.63 MB: each fits the 738 KB buffer the stress city sizes (and
`library.MAX_FILE`, 1 MiB), so the disk can carry all five beside VR1-3 (the node check below confirms the cart lists and loads
them). `build_racer_vr_disk.sh` (local) adds them as `DXFOREST DXBAY DXACRO DXHIGH DXSAND` after VR1-3.

**Node check (25 Nov, the local card `m5all32x`, the browser cart on its disk; `prototypes/cards/racer_32x_check.mjs`, local):**
the cart lists 13 tracks (OVAL CITY SALT NEON GLACIER VR1-3 DXFOREST DXBAY DXACRO DXHIGH DXSAND), refuses none, keeps the
738 KB buffer, and has 141 KB of cart RAM left (>= 64); each DX track loads and flies 600 frames of the flyby at R = 8 with no
trap (at most 668-1,155 polygons a frame, MAXP 6,144). Not tested: driving or racing on the synthesised borders (the race
benchmark only runs in the cost model below, without a trap).

**Frame cost** (`racer_vr_costs.mjs --tracks 8,9,10,11,12` with RACER_ZMD on that disk; plain multiply twin, CPU fill; the model is
~2x pessimistic on this cart: it priced VR1-3's R = 8 flyby at 2.55-3.24 Mc and the board ran it at 50-52 fps):

| | DXFOREST | DXBAY | DXACRO | DXHIGH | DXSAND |
|---|---|---|---|---|---|
| heaviest flyby pose, R = 5 | 2.94 Mc | 2.93 | 3.36 | 2.96 | 2.14 |
| the same, R = 8 | 3.54 (~28 fps model) | 4.55 (~22) | 3.79 (~26) | 3.94 (~25) | 2.38 (~42) |
| lap v2 race, mid-lap, R = 5 | 5.84 | 6.20 | 6.01 | 6.23 | 5.02 |

Against VR1-3 (2.55-3.24 Mc at R = 8) the 32X courses are 1.1-1.4x heavier in the model, except Bay Bridge (1.4-1.8x: its busiest
tile, 165 faces, is in the bridge's view): with the board's ~2x margin, ~35-45 fps expected on the R = 8 flyby.
