# Kestrel Racing: how the engine works, how the cart runs it on KESTREL, what the board measured

Analysis of the port, written at M6 (R82, 27 Nov 2026). Kestrel Racing is an ORIGINAL flat-shaded 3D racer (cart 160
`racer`, `apps/zig/scenes/racer.zig` + `apps/zig/scenes/racer/`) on the engine of freds72's PICO-8 racer (MIT per his
itch.io page; `LICENSE_NOTE.md`), rewritten in Zig integers. The tracks, car, palette, HUD, front end and FM music are
ours; no Sega data ships (the 32X courses and cars are a LOCAL benchmark, never committed). The milestone docs are
`M1.md` .. `M6.md` and `M5_VR.md`; the plan is `prototypes/racer_re/PORT_PLAN.md` (local); the ADRs are in
`docs/project/DECISIONS.md` (25-27 Nov).

## Short answer

- **One frame = five stages**, each a `noinline` function the cost tools bill by name (`frame.zig`): visibility (the
  baked PVS of the camera's tile and yaw bucket, cut at the draw distance R), collect (back-face cull, transform through
  a frame-stamped vertex cache, trivial reject, clip, project, depth key), sort (a counting sort on 1,024 depth buckets,
  far to near), emit (one span emitter) and fill (CPU word stores or CHISEL AFFINE span records).
- **All of it is integer.** Q16 positions, `mulsh16` (one ZM-X instruction on ZIGGY; `fx.zig`), a table reciprocal for
  the projection, PICO-8 16.16 for the physics so the Lua reference runs bit for bit. No float per frame (CLAUDE.md): the
  `g` key's f32 transform is an A/B knob for the FPU, not the default.
- **One plane, two pages**: sky = a copper palette write per line, backdrop = one AFFINE op, HUD = the plane's bands,
  haze = palette entries. No second plane (each costs ~0.59 Mc of compositing on the board).
- **Physics, AI and the race tick at 30 Hz** (every second frame, by frame count); frames interpolate between ticks.
- **The board runs every original track at 60 fps** where it was measured (the oval's flyby and race, the Salt Flats
  race; Neon Docks and Glacier Pass wait for the M5 / M6 cards) and the local 32X courses at 25-40 fps (2.5-4x our faces).
- **`frame_cost` is ~2x pessimistic on this cart, and M6 found why**: its instruction-cache term is 1.3-1.6 Mc of a
  race frame's 2.5-3.4 Mc. Without it the estimate is 1.25-1.78 Mc on our tracks (the board: 60 fps) and 2.1-4.5 Mc on
  the 32X courses (the board: 25-33 fps, i.e. 3.3-4 Mc).

## Architecture

| layer | files | what it does |
|---|---|---|
| the cart | `racer.zig` (Demo), `view.zig`, `present.zig`, `keys.zig` | page flip, camera pick, the stages, HUD and logs; every key |
| camera | `cam.zig`, `zone.zig` | lap v0's script (flyby), fixed poses A-H, the race's chase cameras (far / near / cockpit); roofs pull the far camera near |
| geometry | `pvs.zig`, `frame.zig`, `xform.zig`, `clip.zig`, `project.zig`, `types.zig` | the five stages; cars and skidmarks push into the same list (`carview.zig`, `skid.zig`) |
| fill | `poly.zig`, `sinks.zig`, `draw.zig`, `shadow.zig`, `backdrop.zig` | the span emitter; CPU and AFFINE sinks; the shadow's read-modify-write; the panorama strip |
| colour | `palette.zig`, `haze.zig` | 16 fixed entries + 30 ramps of 8; the copper sky; the haze pool (M6) |
| simulation | `car.zig`, `npc.zig`, `contacts.zig`, `ground.zig`, `race.zig`, `rules.zig`, `session.zig`, `fsm.zig`, `game.zig`, `drive.zig` | freds72's `make_car`, `make_npc`, `find_face`, `face_collide`; the race rules; the table-driven FSM (front end included) |
| data | `trk.zig`, `library.zig`, `trackset.zig`, `carfile.zig`, `cars.zig`, `carmodel.zig` | the track and car binaries, bounded on load; tracks and cars as files (the disk, C:\RACER\) |
| front end | `front.zig`, `menu.zig`, `frontdraw.zig`, `seldraw.zig`, `resdraw.zig`, `options.zig`, `optdraw.zig`, `preview.zig`, `press.zig` | title, select, options, results: FSM states that draw no 3D |
| audio | `audio.zig`, `music.zig`, `sfx.zig`, `voices.zig` | the BARD queue's FM device: three tunes of ours, engine / skid / phrase effects |
| benchmark | `bench.zig`, `report.zig`, `hud.zig`, `refrun.zig` | per-stage `hostMicros`, the OSD, CSV + a view CRC every 60 frames |

Tooling (`tools/racer/`): the converter (`trackc.py`, `kit.py`, `pvs_bake.py`, `bake.py`, `mood.py`), the Track Kit (a
Blender 5.3 add-on: export, budget meter, mood panel; `kit_export.py`, `limits.py`, `walk.py`), the Car Kit (`carc.py`,
`carcheck.py`), the Python reference renderer (`ref_render.py`, compared pixel for pixel by the gate), the reference
physics harness (freds72's Lua under z8lua, local), and the LOCAL 32X importers (`vr32x_*.py`, code only).

## The engine's maths

- **Units.** A world unit is ~8.3 m; a tile is 8 units on a 32 x 32 grid; vertices are i16 in 1/128 unit; positions and
  view space are Q16 (`fx.zig`); normals Q14; the depth key is 1/8 unit.
- **Transform.** The view matrix rows are Q25 (Q16 << 9), so a vertex in 1/128 units goes through `mulsh16` directly:
  nine `mulsh16` a vertex, cached for the frame (a vertex shared by four faces is transformed once).
- **Cull.** Back faces by the plane test `n . eye > cp` with the eye in Q7 (no transform needed); trivial reject by an
  outcode AND over the face's vertices.
- **Clip.** Sutherland-Hodgman against the near plane and a guard band (|x|, |y| <= 3 z): every projected vertex stays
  inside the edge walker's Q4 range, so the fill needs no screen clip beyond the rows and the width.
- **Project.** x = 160 + F x / z through one reciprocal (a 256-entry table + one Newton step) and two `mulsh16`, Q4.
- **Sort.** The painter's order from a counting sort on the face's MEAN view depth (freds72 sorts by a projected
  distance; the mean keeps decals with their parent and is one add). A face's decals take its key; a car takes one key
  (its middle, never below the ground face under it) and keeps its model's own order (shadow, wheels, hull, cabin /
  wing by the eye's side). 1,024 buckets, stable, far to near.
- **Visibility.** The converter bakes, per camera tile and 16 yaw buckets, the tiles a DDA of 33 rays reaches within
  R_BAKE steps plus a 3 x 3 neighbourhood; the cart cuts the list at R. Tiles off the baked set use the run-time DDA.
- **Physics.** PICO-8 16.16 throughout, trig and sqrt tables built from formulas so the integers match the Lua's; the car
  is a velocity, an angle and an angular velocity with front-tyre slip, lateral drag and wheel-spin grip; the ground is
  `find_face` (the previous face first, then the tile's ground faces; since M5 height-aware for crossings); walls are the
  faces' border edges as 2D planes; contacts are two circles a car. The AI is freds72's PID on the racing line.

## The fill paths

`poly.Emitter` walks each edge from its upper end in Q4 and emits spans (y, x0, x1, colour). It never knows the sink:

- **CPU** (`sinks.CpuSink`): head and tail bytes, aligned word stores between (the board traps a misaligned word).
- **AFFINE** (`sinks.AffineSink`): a 24-byte CHISEL AFFINE record a span, sampling a 256-byte flat texture (texel i =
  index i, no colour key), so an AFFINE copy is a flat fill. The records fill half of a 2 x 2,048 ring and each half is one
  CHISEL op, which runs while the CPU collects and sorts. A shadow span fires the queue and waits (`blitSync`): it reads
  the plane.
- **Shadow** (`shadow.zig`): each pixel one ramp level down (index - 1 inside a ramp; a ramp's bottom, entries 0-15 and
  the haze pool kept), four pixels a word by SWAR. Key `y`: the arcade checkerboard.
- **Backdrop**: one keyed AFFINE op from a 1024 x 48 strip, offset by the yaw.

CHISEL TRIANGLE was ruled out in the plan (4.6-6.1 clocks a pixel). The two paths are byte-identical (a gate check on
every track and in the race). On the board AFFINE won: equal on the oval, the city's cart cycles -43 % at R 4.

## Colour

Index = 16 + ramp x 8 + level. Track faces carry a BAKED level (`bake.py`: the face normal against the track's fixed sun,
levels 4-7; no run-time light), so the fill writes one byte per face. The sky gradient is entry 1 on the copper (a real
raster: the colour register rewritten per line); the far ground beyond R is entry 4 at the baked flat level, so the draw
distance has no seam. M6's haze adds banded copies of the face colours in the palette's spare entries (`haze.zig`,
`M6.md`).

## What the board measured (KESTREL: Zynq 7010, ZIGGY rv32im at 100 MHz, FRESCO, CHISEL v2)

| date | scene | board | model (frame_cost) |
|---|---|---|---|
| 24 Nov (M1) | oval flyby at R 5 and R 8, CPU and AFFINE fill | 60 fps, 0 missed | 1.1-1.3 Mc (60) |
| 24 Nov (M1) | stress city at R 4 / R 8 | 42-48 / 22 fps | 2.99 / 5.65 Mc (~33 / ~18) |
| 24 Nov (M3) | oval race: the grid with 8 cars, mid-race, bench lap v2 | 60 / 60 / 60 fps | ~53 / ~33 / ~33 fps |
| 24 Nov (M4) | BARD with the music and the effects | ~50 % | 61 % avg / 69 % peak |
| 25 Nov (M5 step 0) | local Virtua Racing arcade tracks | ~40 fps | 18-26 fps |
| 26 Nov (M5 step 3) | Salt Flats grid and mid-race; 32X DXFOREST / DXBAY grid | 60; 25 / 33 fps | ~2.9-3.3 Mc |
| 26 Nov (M5 step 4) | title, select, results; Salt Flats race (pilot); DXBAY race | 60; 60.3; 30.2 fps | |

The M6 table per track and POV is in `M6.md`. Two lessons from it: the model's instruction-cache term over-bills this
cart (the board ran 60 where the model said 33); and the board's real limit is the face count in the collect stage (the
city and the 32X courses), not the fill.

## Lessons

- **Measure the fill path on the board before choosing it.** The model put CPU and AFFINE within 1-4 %; the board
  showed AFFINE 43 % cheaper on a dense track (the CPU span stores were undercounted).
- **A bit-exact reference pays for itself.** Physics, AI and contacts compare per tick with freds72's Lua (z8lua); the
  30 Hz tick kept every constant his, and each later change (the car scale, the height-aware ground, the camera zones)
  proved "physics unchanged" by a CRC list, not by eye.
- **Pins split by purpose.** View pins (rows 12-187), physics CRCs, HUD hashes and result hashes are separate, so a look
  change (the GT car, the scale, the haze) moves only the pins it should, and each move is listed in its milestone.
- **Keep the off state byte-identical.** Every new look (shadow, scale, zones, haze) has a key and an off state equal to
  the previous milestone's hashes; M6's haze harness proves it against M5's own pins.
- **Files, not builds.** Tracks and cars as bounded, refusable files (one cart for the shelf and the local 32X data)
  removed the per-data builds and opened the cart to the user's own tracks.
- **The model is a guide; the board is the profiler.** Rank stages and compare A/B variants with frame_cost on the same
  cart; read its total without the I$ term for this cart; never promise an fps from it.
