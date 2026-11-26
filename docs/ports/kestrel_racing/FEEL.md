# Kestrel Racing: the 32X feel (R82, 27 Nov)

Matt (27 Nov): fit OUR physics to the 32X's driving feel ("yes!"), keep a toggle for the shadow headroom, then "scale up the
cars, and give speed". This adds a second physics model, **ARCADE** (the default), beside freds72's, now called **CLASSIC**,
which is unchanged and still the Lua's bit for bit. Nothing from the 32X ROM is in the cart, the committed files or this
page: every number below is ours or a residual against behaviour **measured from the 32X and kept locally**.

## What is measured from the 32X (local), and what is solid

The 68000's straight-line model was read from the code into a small simulator (local: `prototypes/racer_feel_local/` in
the agent worktree, from `prototypes/racer_re/vr_local/32x/re/py/accel.py`). No emulator was run, so it was checked against
the listing instead, routine by routine:

- **Solid:** the force step (torque by rpm x gear ratio x throttle, the resistance by display speed, the grip limit, the
  divide into the speed word, the rpm from the speed), the AT gearbox (up and down shifts), the pedals' ramp, the off-road
  drag (speed squared, halved with one or two probes off). Adding what the first sim left out (a per-car speed cap that
  clamps the display speed, the 16-bit truncation before the divide, the downshift, the throttle starting below zero)
  changes nothing at full throttle: **the uncapped sim's top speed equals the ROM's per-car cap entry for all six
  class / gearbox cases**, two independent mechanisms agreeing. The throttle-off coast and the off-road settle come out of
  the same code.
- **Assumed, not validated:** the frame rate. The 68000 steps once per rendered frame; the targets take its nominal
  20 fps (the disassembly project's figure, and the rate at which its speedometer matches its displacement within a few %),
  so a 32X frame is 1.5 of our 30 Hz ticks. If the real rate differs, every target time scales with it.
- **Not used:** the per-car cap index's meaning (it varies by an index we did not decode), manual gearboxes, the AI's
  per-group factors, the crash thresholds' values.

## The ARCADE model (ours)

`apps/zig/scenes/racer/arcade.zig`, its Python twin `tools/racer/feel.py`, the fit `tools/racer/feel_fit.py`:

    s' = s + thr x (net(s) + drag(s)) - drag(s) - off x K x s^2 - brake x B        (never below -MAX_DEC; 0 <= s' <= max(s, top))

per 30 Hz tick, on the FORWARD speed only. `net` (full-throttle acceleration, 5 control points, 0 at the top) and `drag`
(coast-down, 3 points) are piecewise-linear curves of OUR control points; the pedals ramp 32/256 a tick (a quarter second);
`off` is 1 with three or four wheels off the asphalt, 1/2 with one or two. Everything else of a tick is freds72's: the
steering, the tyre slip, the yaw, the sideways damping (0.97), the car-vs-car contacts. The engine note's rpm comes from a
cosmetic 6-speed gearbox of ours.

Three classes (the options' CAR CLASS, key M): FORMULA (top 330 km/h), STOCK (285), PROTO (380), tops rounded by us.
**The fit:** coordinate descent on the integer twin over the curves' values (speeds fixed), minimising the squared relative
error of the time to each speed from 50 km/h to near the top, then the coast-down times, then the off-road settle speeds;
the net curve may never rise with speed and the drag never fall (physical curves; the first fit had a STOCK bump).
**Residuals** (our time against the 32X's, per speed band; FORMULA / STOCK / PROTO):

| band | FORMULA | STOCK | PROTO |
|---|---|---|---|
| 0-50 .. 0-150 km/h | -3.3 .. +3.7 % | -3.3 .. +6.2 % | -3.0 .. +4.8 % |
| 0-175 .. 0-275 | -1.5 .. +1.8 % | -2.0 .. +2.0 % | -4.5 .. +1.8 % |
| the top end (0-300 and up) | -6.5 .. +4.2 % | +3.9 % | -1.5 .. +4.1 % |
| coast-down from the top | -8.7 .. +3.2 % | -2.5 .. +2.0 % | -0.9 .. +0.5 % |
| off-road settle speed (3-4 / 1-2 wheels off) | -5.4 / +5.6 % | -2.1 / +2.2 % | -0.5 / +0.9 % |

Our FORMULA: 0-100 km/h in 56 ticks (1.9 s), 0-200 in 3.8 s (CLASSIC: 1.5 s and 3.1 s, and a top reached much sooner).
Brake 120 km/h a second, no deceleration past 140 km/h a second (an off-road plunge at speed is capped).

**Oracles.** The engine: `feel.py` is the twin, `feel_params.zig` is generated from it with each class's pins (ticks to 100
and 200 km/h, the CRC of 600 ticks of full throttle and of the coast-down), `arcade_test.zig` replays them through the Zig.
A whole race (2-D handling, walls, contacts) has no second implementation: the Zig model is the oracle, pinned by an
oval race CRC (`arcade_test.zig`) and a Salt Flats race result (`racer_feel.mjs`). A Python twin of freds72's lateral model
would be a second copy of the Lua the CLASSIC pins already prove; the part we own and fitted is the longitudinal one.

## Scale: the world, the cars, the speed (Matt: "scale up the cars, and give speed")

freds72's speedometer is `900 x units a tick`, so his unit is **8.33 m** (332 km/h = 11.07 units/s). The 32X does the same
(a frame moves the car by its speed word / 16, in 1/128 units: 332 km/h = 11.5 units/s at 20 fps): **at 332 km/h the 32X
itself moves at about half of 92 m/s on its own roads**, which are 2.75-3.6 units wide (median 3.3; a real road is ~13 m,
so a 32X unit is ~4 m). Our Track Kit tracks are authored at about a metre a unit (roads 10-12 units, Salt Flats' lap
"684 M" on the select), so at freds72's speed they felt like 40 km/h. That is the "332 feels like 10 km/h".

The ARCADE model keeps the velocity in freds72's units (the km/h on the HUD, the handling, the fit are unchanged) and moves
the car `world` times further a tick: `pos += vel x world`, in sub-steps of at most 0.4 units (so no wall or segment is
skipped; at most 16). The car is drawn `car` times its model (the camera's distance and height grow with it, so the car
fills the screen as before and the road around it reads `car` times narrower), and its colliders grow too. Both are
per-track, in the mood block's optional tail (`tools/racer/mood.py`: a 36-byte block, Q8; absent = 1, every earlier file):

| track | road (units) | metres a unit | world | car | arcade top (units/s) | flyby (units/s) | top / flyby |
|---|---|---|---|---|---|---|---|
| oval (no tail) | 6 | 8.33 (freds72's) | 1.00 | 1.00 | 11 | 38 | 0.29 |
| Salt Flats | 12 | 2 (Kit) | 4.17 | 2.50 | 46 | 57 | 0.81 |
| Neon Docks | 11 | 2 | 4.17 | 2.50 | 46 | 53 | 0.88 |
| Glacier Pass | 10 | 2 | 4.17 | 2.50 | 46 | 84 | 0.55 |
| 32X courses (local) | 2.75-3.6 | 13 m / width | 1.76-2.32 | 1 (decoded cars) | 19-26 | 36-57 | 0.44-0.70 |

**The flyby check (Matt: "the flyby speed looks more accurate as the car's potential top speed").** The flyby covers a lap
in 720 frames (12 s), so its ground speed is lap / 12. The arcade top lands at 0.44-0.88 of it in world units; on screen
(ground flow at the bottom row, far chase POV, F = 160) the arcade car at its top gives 1,440 px/s on our tracks and
1,520-2,010 on the 32X courses, against the flyby's 1,330-3,130 px/s and CLASSIC's 864: in the flyby's range, ~2x CLASSIC.

**Our Track Kit tracks** are the compromise: at a real metre a unit (their roads' width) the car would be 5x bigger and a
lap would last 7 s at the top (684 m); the Kit's default (`kit.py KIT_WORLD / KIT_CAR`, a `world` / `car` the export can set)
is 2 m a unit: roads 20-24 m (wide), laps 1.3-2 km, the car 4.5 m long. Regenerating the Kit tracks with roads a third as
wide (or laps three times as long) would give both real widths and real laps; not done (the lead's call).

## Walls and off-road (our code for the 32X's behaviour, `wall.zig`)

- **Off-road:** the four wheel corners are looked up on the ground every tick; 3-4 off the asphalt = the full off-road
  drag, 1-2 = half (the 32X's rule; our constant K, fitted to its settle speeds).
- **Walls:** a car whose centre comes within the collider of a wall edge is rolled back to the last free quarter of its
  sub-step (no push-out unless even the first quarter is blocked, a car already sliding along the wall), turned onto the
  surface's heading (the racing line's, or the wall's own where the line runs into it: the outside of a hairpin) and keeps
  cos(heading error) of its speed (at least a quarter).
- **Hard crash:** over 150 km/h and more than 30 degrees off the heading (thresholds ours) the car is put back on the
  racing line one segment on, stopped (`crashes` counts them).

## The AI: speed cues

A racing-line entry's flags word carries a cue in its high byte (`trk.LINE_CUE`; 0 = none, the default of every old
file): the speed, x/256 of the FORMULA top, the AI holds there. The Track Kit bakes them (`tools/racer/cues.py`: each
segment's corner speed from the radius through its neighbours under our lateral limit, then lowered so a car can brake
to every slower one ahead; the world scale shrinks the radius in the physics' units). In ARCADE the AI (`npc.arcadePedals`)
holds 250/256 of the next segment's cue: throttle under it, brake over it by 1/16. With no cue (the oval) it keeps
freds72's rule (brake while steering hard) on our brake pedal. The 32X import fills the cues locally from its first AI
line (255 + its cue x 0.6, our gain; the per-group factor is not decoded), never above our geometric bake.
Headless (the AI flying all 8 cars, 100 s): Salt Flats 6 laps, Neon Docks 5, Glacier Pass 3, no crash, at most 14 wall
touches a car; the 32X courses 1.8-3 laps with 30-80 touches and up to 4 crashes; DXHIGH loses a car at its crossing.

## Choosing the model

- Options screen: **PHYSICS** ARCADE / CLASSIC (key T), **CAR CLASS** FORMULA / STOCK / PROTO (key M); both RAM only.
- The reference's drivers are CLASSIC by construction: the bench laps (b, x), the recorded driver and the pilot under `a`
  (game.physics). So every Lua pin (lap v1, lap v2, the 3-lap race, the front end's race) is unmoved.
- Key L: the AI's controller flies the player in the PHYSICS option's model (the arcade harness' driver).
- Free driving (n, M2's bench on the oval) stays CLASSIC.

## The shadow headroom (local 32X import; the code committed)

On DXFOREST much of the road is at its ramp's bottom, where the one-darker shadow cannot go. `vr32x_import.py
--shadow-headroom` stores, beside each face's colour, the same colour kept one level off the bottom (level 0 -> 1) in the
face record's spare alternate byte (`alt` byte 2); the cart draws it when the toggle is on (`project.headroom`): key 9, or
the SHADOW row's third value REAL HEADROOM (offered only on a track that has it). The palette is untouched; the cost is a
byte test per polygon. FLAT shading only (LIT / SOFT keep their own levels). Default off.

## Also in this branch

- Backspace leaves a running bench lap (x or b) for the select; without it the bench's CRCs are untouched.
- The OSD (key o) puts every option's state on its top line: `CPU MS FL RL H1 R8 ARCF FAR M1 L3` (fill, multiply, shading,
  shadow RL / HR / CK, haze, R, physics + class initial, POV, music, laps).
- AFFINE vs CPU fill (Matt's board run, DXFOREST x bench 27-31 fps either way; ours, M6 32X card: races 48-57 fps with
  no fill difference beyond noise): CPU stays the default, the fill is not the bottleneck on the 32X courses.
- The 32X car files (143-188 faces a model): no fixed per-frame buffer can overflow (a car's vertex cache is the file's
  bound, 256; 8 such cars + a 32X track at R 8 is ~2,700 polygons of MAXP 6,144, and past it polygons are dropped and
  counted, never written past the end). The M6 32X black screen is not explained by them.

## Tests

`arcade_test.zig` (the twin's pins for every class, `--break feel`, pedals, the gearbox note, off-road, the line heading,
a wall and a crash, an oval race pinned, a Salt Flats race, the scale block's refusals, sub-steps, cues), the CLASSIC tests
untouched; `tools/tests/test_racer_feel.py` (twin, fit, cues, scales, headroom, the 32X feel logic on synthetic data);
`apps/harness/racer_feel.mjs` + 2 gate lines (`--break feel`).
