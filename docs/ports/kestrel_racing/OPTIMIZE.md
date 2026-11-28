# Kestrel Racing: the board optimisation (R82, night of 27 Nov)

Branch `perf/racer-board` (from `feat/racer-board-batch` 68a1a3e6). Goal (Matt, 27 Nov): every course >= 30 fps IN A RACE
with the HUD on, 60 on our light tracks, as close to 60 as possible on the 32X ones, without changing the look. Cards:
`prototypes/cards/build_racer_opt.sh <rev>` stages `opt` (public) and `optx` (LOCAL: the 32X data + `-Dracer_music`;
`ONLY_X=1` builds it alone), `install_racer_opt.sh` retires the previous card to `/mnt/sd/CARTS/retired/` first.

## How it is measured

The board is the profiler (the frame-cost model was off by 2-10x on the parts that mattered: it never saw the misaligned
traps nor the real price of a race tick). Every number below is `glass ctl stats 5` on KESTREL, taken **in the race**,
~9 s after the start (the cars moving, the ticks running), one track per load:

    load card; l (out of the title); t x n (the track); e (race) + L (the AI pilot drives us) + s (start), or x (bench);
    wait 9 s; o (the OSD); stats 5

(`prototypes/cards/racer_opt_tools/race.sh`, `table.sh`). Board `t` order on the 32X card: OVAL CITY SALT NEON GLACIER
DXFOREST DXBAY DXACRO DXHIGH DXSAND (CITY and GLACIER were missing on the batch card: dropped for cart RAM, see below).
A race runs R 8 and the ARCADE physics; the x bench runs R 5 and CLASSIC: the bench is not a proxy for a race.
Matt's earlier list ("bench, 5 s each in t order") was mostly the grid and the countdown (cars still, no ticks): it
reads higher than an in-race number on the same card.

New switches (hide.zig, off by default, no pin moves): `(` cars, `)` picture HUD, `{` panorama, `}` shadows, `#`
scenery, `$` ground. The OSD (o) now reads `T V C A S K F H = frame fps`, in units of 100 us: T the game's update (the
race ticks), A the cars (split from C, collect). Key `` ` `` shows probe timers (prof.zig) instead of the state line:
page 1 the tick (P0 player physics, P1 AI steering, P2 AI physics, P3 car pushes, P4 snapshots + smoke, P5 the session
tick), page 2 the cars (P6 model view + footprint key, P8 faces + shadows, P9 wheel posing, P10 smoke, P11 picture HUD).

## Where the time went (DXBAY race, batch card, 18 fps, cart 5.2 Mc)

| part | ms a frame | what |
|---|---|---|
| T tick | 10.9 | ~1.7 race ticks a frame (pace.zig runs the ticks the clock owes): ~6.5 ms a tick, ARCADE physics + AI + pushes |
| C collect (track) | 10.2 | the PVS tiles' faces (R 8 vs R 5 barely moves it) |
| A cars | 13.3 | 8 cars: of it 5.2 ms posing the wheels, ~1,800 misaligned traps a frame |
| F fill | 11.8 | CPU spans (6.6 with the cars hidden); the AFFINE path is no cheaper (the CPU walks the edges either way) |
| H HUD | 0.5 | the picture HUD is NOT the problem: hiding it moves cart_c by noise |

## Results (fps, glass ctl stats, in race / x bench; rows by the track name on the HUD)

| track | batch race | batch bench | opt2 race | opt2 bench |
|---|---|---|---|---|
| OVAL | 35.2 | 40.7 | 39.1 | 42.5 |
| SALT | 23.8 | 38.2 | 31.4 | 41.1 |
| NEON | 24.4 | 41.3 | 31.6 | 43.3 |
| GLACIER | (not listed: no RAM) | | 30.9 | 44.0 |
| DXFOREST | 17.7 | 24.0 | 21.6 | 25.6 |
| DXBAY | 18.1 | 23.6 | 21.8 | 26.0 |
| DXACRO | 18.9 | 23.2 | 23.0 | 26.0 |
| DXHIGH | 16.1 | 20.9 | 20.9 | 23.8 |
| DXSAND | 20.9 | 28.3 | 26.5 | 31.1 |

The 32X card (RACER BATCH 32X / RACER OPT 32X) races its FORMULA set (CAR.KCR: 143 faces for the player, ~71 for an AI
car) on EVERY track, ours included; the public card races the GT. CITY is not raceable (its race and bench rows are the
oval's). opt2 = 6ba5bfcf (gated green). A configuration repeats to ~0.2 fps; between cards, the race's own course (pace
gives more ticks to a slower frame) moves a track by up to ~2 fps.

## What each change bought

1. **Misaligned traps in the cars** (~1,800 a frame -> 41): the wheels' face copy lowered to i64 loads at offsets 2
   and 18, `[3]i16` vertex reads merged into 32-bit loads, `project.Key`'s two bools stored as one i16 at an odd stack
   offset. Wheel posing 5.2 -> 1.3 ms on DXBAY.
2. **fix.sqrt / fix.div** in 32-bit words (the 64-bit forms are libgcc calls on rv32): same integers (a million-operand
   comparison in fix_test.zig).
3. **Ground normals** (groundmemo.zig): a face's side tests before its normal; the plane and wall normals remembered in
   a table keyed by the vertices themselves (no invalidation on a track load). Same integers.
4. **Cars out of view** (carcull.zig): a bounding-sphere test against the view planes before any vertex.
5. **Cart RAM**: u16 frame stamps and a 20-byte vertex cache entry gave back ~120 KB: GLACIER and CITY fit on the 32X
   card again (they had been dropped at the library scan), and the public card keeps GLACIER (the gate caught it gone).
6. **Car pushes**: circle pairs that cannot overlap are not measured (vec.len is three divides and a sqrt).
