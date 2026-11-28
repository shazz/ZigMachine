# Kestrel Racing: the board optimisation (R82, night of 27-28 Nov)

Branch `perf/racer-board` (from `feat/racer-board-batch` 68a1a3e6, not merged). Goal (Matt, 27 Nov): every course >= 30
fps IN A RACE with the HUD on, 60 on our light tracks, as close to 60 as possible on the 32X ones, without changing the
look. Every commit keeps the pixels (the gate's pins are unchanged; `./build.sh --only racer` green at every card).
Cards: `prototypes/cards/build_racer_opt.sh <rev>` stages `opt` (public: our tracks, the GT) and `optx` (LOCAL ONLY: the
32X courses and cars + `-Dracer_music`; `ONLY_X=1` builds it alone); `install_racer_opt.sh` retires the card already on
the shelf to `/mnt/sd/CARTS/retired/` first. On the board: RACER OPT, RACER OPT 32X.

## How it is measured

The board is the profiler. Every number is `glass ctl stats 5` on KESTREL, **in the race**, ~10-15 s after the start:

    load card; l (out of the title); t x n (the track); e (race) + L (the AI pilot drives us) + s (start), or x (bench);
    wait 9 s; o (the OSD); stats 5

(`prototypes/cards/racer_opt_tools/race.sh`, `table.sh`; rows are labelled from the track name in each run's screenshot).
That window has the whole pack in view: it is the worst case of a race. A race runs R 8 and the ARCADE physics; the x
bench runs R 5 and CLASSIC: the bench is not a proxy for a race. A configuration repeats to ~0.5 fps; between cards the
race's own course (pace.zig gives a slower frame more ticks) moves a track by up to ~2 fps.

The baseline list of 27 Nov ("x bench, 5 s each in t order") was taken straight after each switch: the grid and the
countdown (cars still and bunched, no ticks yet). It also had ten names where the 32X batch card listed eight tracks
(CITY and GLACIER were not on it: dropped at the library scan for cart RAM), so its GLACIER / NEON rows were other
tracks. And the in-picture HUD was not the cause of 17 vs 36: that was race vs bench (R 8 + ARCADE + paced ticks).

The frame-cost model (apps/harness/frame_cost.mjs) never saw the misaligned traps; once they were gone it agreed with the
board within ~20 % on the render (fill, collect, cars) and ranked the cuts between card builds (a card takes ~25 min, a
model run seconds). It under-counts a race tick.

**Switches** (hide.zig, off by default, no pin moves): `(` cars, `)` picture HUD, `{` panorama, `}` shadows, `#` scenery,
`$` ground. The OSD (o) reads `T V C A S K F H = frame fps` in units of 100 us: T the game's update (the race ticks), A the
cars (split from C), H the bands and the picture HUD. Key `` ` `` shows probe timers (prof.zig) instead of the state line,
`k:v` with v in units of 10 us a frame: page 1 the tick (0 player physics, 1 AI steering, 2 AI physics, 3 car pushes),
page 2 the cars (6 every car's prep: model view, cull, floor key; 7 the player's car; 8 every car's faces + shadow; 9 wheel
posing; 10 the shadows; 11 the picture HUD). **Opt-in, changes the picture** (carlod.zig, off by default): `-` the AI
cars' far model past 3 units / always, `=` no wheel turning past 3 units, `;` no shadow past 12 units.

## Results

The installed cards are e7d93c58 (measured 28 Nov 03:15-03:45). 32X card (RACER BATCH 32X -> RACER OPT 32X: the FORMULA
set on every track, ours included), fps race / x bench:

| track | batch race | batch bench | opt race | opt bench |
|---|---|---|---|---|
| OVAL | 35.2 | 40.7 | 43.8 | 47.8 |
| SALT | 23.8 | 38.2 | 35.2 | 45.8 |
| NEON | 24.4 | 41.3 | 35.8 | 48.4 |
| GLACIER | (not on the card) | | 35.0 | 49.2 |
| DXFOREST | 17.7 | 24.0 | 25.0 | 29.7 |
| DXBAY | 18.1 | 23.6 | 25.4 | 30.1 |
| DXACRO | 18.9 | 23.2 | 26.5 | 29.7 |
| DXHIGH | 16.1 | 20.9 | 24.2 | 26.8 |
| DXSAND | 20.9 | 28.3 | 30.5 | 35.4 |

Public card (RACER BATCH -> RACER OPT: our tracks, the GT), race / bench:

| track | batch race | batch bench | opt race | opt bench |
|---|---|---|---|---|
| OVAL | 45.2 | 53.9 | 55.8 | 59.8 |
| SALT | 37.1 | 51.7 | 47.5 | 58.8 |
| NEON | 31.8 | 55.2 | 43.0 | 60.2 |
| GLACIER | 30.5 | 55.6 | 41.5 | 60.2 |

Later in the race (25-30 s in, the pack strung out) DXBAY reads 18.1 -> 28.4. Flyby (l): CITY (public) 19.5 -> 31 fps (its OSD reads ~58: the frame waits on something outside the cart, open); DXBAY
34.2 -> 40.1. CITY is not raceable (its race rows are the oval's).

**Targets:** missed. The 32X courses race at 24-26.5 fps (DXSAND 30.7); our tracks race at 41-55 on the public card and
the bench reaches 60 on all four. **The floor:** with the cars hidden a DXBAY race runs 33 fps (cart 2.4 Mc), so even
free cars would not reach 60 there; the cars cost ~1.4 Mc of that race (8 cars: A 9.4 ms + their fill + the ticks a
slower frame owes).

## The ladder (DXBAY race, 32X card)

| card | commits | fps | cart Mc | what moved |
|---|---|---|---|---|
| batch | 68a1a3e6 | 18.1 | 5.2 | T 10.9 C 10.2 A 13.3 F 11.8 H 0.5 (+2.0 HUD outside the OSD) |
| opt1 | ..eb885276 | 21.4 | 3.9 | misaligned traps out of the cars (~1,800 a frame -> 41); fix.sqrt / fix.div in 32-bit; ground normals remembered; cars out of view culled |
| opt2 | ..6ba5bfcf | 21.8 | 3.9 | u16 stamps (cart RAM: GLACIER and CITY back on the 32X card); fix.div long division; car pushes skip far pairs |
| opt3 | ..914f8af8 | 23.5 | 3.7 | the emitter reads the kept records directly, no divide an edge; mulsh knob read once; tile cull; AFFINE halves of 512 |
| opt7 | ..418a032a | 23.2 | 3.6 | sky fills (no gain: K is the backdrop's span list); opt-in far cars |
| opt8 | ..fbc75aec | 23.0 | 3.7 | AI tick a phase at a time; car prep phase |
| opt10 | ..8f28c89b | 24.8 | 3.5 | AFFINE fill by default (board-checked byte-identical to the CPU's); clz in compares |
| opt11 | ..82b6c7e8 | 25.4 | 3.4 | HUD text pixel by pixel (picture HUD 2.0 -> 1.1 ms); AFFINE records three stores |
| opt12 (installed) | ..e7d93c58 | 25.4 | 3.4 | a shadow in a haze band not transformed; file sizes |

Where a DXBAY race frame goes now (OSD, ms): T 4.0, C 7.5, A 9.4 (prep 1.5, the player's car 1.9, shadows 1.8, wheel
posing 1.2), F 8.8, H 1.6, K 0.6, S 0.3; ~1.4 more in the cart outside the OSD; FRESCO ~4.3. Hiding each item (opt10):
cars -14.8 ms, scenery -7.6, ground -5.0, shadows -4.0, picture HUD -2.3, panorama -0.4.

## What each change bought

1. **Misaligned traps in the cars** (~1,800 a frame -> ~40): the wheels' face copy lowered to i64 loads at offsets 2
   and 18, `[3]i16` vertex reads merged into 32-bit loads, `project.Key`'s two bools stored as one i16 at an odd stack
   offset. Wheel posing 5.2 -> 1.3 ms on DXBAY.
2. **fix.sqrt / fix.div** in 32-bit words (the 64-bit forms are libgcc calls on rv32): the same integers (a million-operand
   comparison in fix_test.zig).
3. **Ground normals** (groundmemo.zig): a face's side tests before its normal; the plane and wall normals remembered in a
   table keyed by the vertices themselves (no invalidation on a track load). The same integers.
4. **Cars out of view** (carcull.zig) and **PVS tiles out of view** (tilecull.zig): bounding spheres against the view
   planes, before any vertex; tests prove nothing kept changes.
5. **Cart RAM**: u16 frame stamps and a 20-byte vertex cache entry gave back ~120 KB: all ten tracks on the 32X card, and
   the public card keeps GLACIER (the gate caught it dropped when a table took the last 4 KB).
6. **Car pushes**: circle pairs that cannot overlap are not measured (vec.len is three divides and a sqrt): P3 1.3 -> 0.3.
7. **The emitter**: no i32 copy of every kept polygon, no `% n` (a divide) to find each next edge.
8. **The AFFINE fill by default**, in halves of 512 spans so CHISEL works while the CPU walks the edges; a span record is
   three stores. ~1.3 ms on a 32X race. A paused race frame on the board is byte-identical both ways (DXBAY and the oval,
   cars and shadows in view). Fixed on the way: the course / car selects' fill began the AFFINE sink on the wrong page.
9. **The picture HUD**: its glyphs are stored pixel by pixel when the string is on screen (was ~1,250 clipped rects a
   frame): ~2.0 -> ~1.1 ms. Its time now shows in the OSD's H.
10. **Smaller**: phase-ordered AI tick and car prep (each phase's code stays in ZIGGY's 16 KB I$), mulsh knob read once a
    vertex, clz in five compares (rv32im has none), a shadow in a haze band not transformed, under.key's cheap test first.

## The opt-in far cars (not recommended)

Measured on DXBAY: `- = ;` together buy ~+0.6 fps (A 9.4 -> 8.1 ms), because the AI cars past 6 units already draw
their far model (the pack ahead is far); in a paused frame the switches changed one near car (452 pixels). Not worth
changing the picture for.

## What next

- **The cars** are the biggest item left and every exact cut is now small: 8 cars x (prep, shadow, faces) at ~500
  cycles a face. The real lever changes the picture: pre-rendered car views (sprites from N yaw x size, keyed CHISEL
  blits in the painter's order), as the 32X itself would need at our resolution. Matt's call.
- **Shadows** (4 ms on DXBAY): each car's shadow waits for CHISEL before the CPU darkens the plane; a darken that CHISEL
  could do itself (a LUT op on the destination) would remove the waits: a CHISEL feature, not a cart change.
- **The 32X tracks' faces**: the importer reports soft limits exceeded (DXSAND: 5,215 faces with decals, 129 in its
  busiest tile); scenery is 7.6 ms of a DXBAY frame. Merging coplanar same-colour faces in vr32x_import.py would cut
  collect and fill without a visible change (to be proved per track).
- **CITY's flyby** reads 58 fps on the OSD and 31 on glass: something outside the cart waits; worth one probe.
