# Kestrel Racing: the bug pass (R82, 27 Nov)

Matt's board session of 27 Nov listed eight faults. Branch `feat/racer-bugpass` (from `feat/racer-32x-feel`). Each item:
the cause, the fix, the test. Nothing from the 32X ROM, its decoded data or a local tune is in a committed file; the local
32X measurements below were taken with `RACER_ZMD=<a local disk>` and are numbers only.

## 1. Road decals drawn over the car

- **Cause.** A decal (the start line, a road marking) takes its PARENT ground face's key; a car takes ONE key, its middle's
  depth, raised only to the key of the face under its centre and under the shadow corner nearest the eye. A decal whose
  parent face was nearer than the car's middle (a long road quad running back toward the camera) but under the car's rear
  was drawn after the car, over it.
- **Fix.** `racer/under.zig`: a car's key is never below the key of ANY kept ground face its footprint (the shadow's box,
  item 8, at the car's scale) overlaps in x/z on the car's own deck (a separating-axis test, a face's box first; faces at
  or under the centre face's key are not tested). The car is pushed after collect and the sort is stable, so on a tie the
  decal is drawn first. Tyre smoke (item 6) takes its own depth, never below its ground face's key.
- **Test.** `under_test.zig`: a car put over every decal of Salt Flats and Glacier Pass (centre, half and most of its length
  past it, four headings, the far chase camera at the ARCADE scale): 2,676 + 2,736 placements where the footprint covers
  the decal, the car's key is never below the decal's; the M5 rule (`--break under`, key O: the centre's face and the
  footprint corner nearest the eye) paints 66 of them over (the centre's face alone: 626). `racer_bugpass.mjs` 1: an ARCADE race on Salt on two machines, decals on and off, no car pixel
  differs over 900 frames (that race never puts a car where the old rule failed: the native sweep is the mutant's check).

## 2. Track faces sometimes disappear

- **Investigated with an oracle** (`racer/oracle.zig`, key 2): the frame draws, beside the baked PVS list, every non-empty
  tile the camera's REAL view wedge (from the eye, not its tile's centre) crosses within the PVS' own distance, and logs
  `racer,pvs,<lost>,<kept>,<blinks>,<dropped>` each frame: faces kept that no PVS tile holds, faces kept two frames ago and
  now but not in between, polygons past the 6,144 cap.
- **Found (headless, ours and the five 32X courses):** the PVS loses no face on any flyby lap and at most one face in a few
  frames of a 1,500-frame race; nothing is ever dropped at the cap (641-757 polygons kept at most in a 32X race); no clip
  failure, no key overflow (depths stay under the 128 units the 1,024 buckets hold). The one-frame "blinks" are (a) faces
  at the screen edge where the FLYBY camera's yaw reverses for a frame (the racing line's yaw is noisy on the 32X lines:
  up to 144 faces in one frame on DXHIGH's flyby, 9-12 a lap on our tracks) and (b) faces seen edge-on.
- **The painter's order** (the other way a face "disappears": kept, then painted over by a farther one keyed nearer):
  the oracle's last number counts the kept non-ground faces keyed under the ground face below their foot. ~18-36 a frame
  in the 32X races, ~23-26 on ours: the same on both, so no 32X-specific sign of it (the count is coarse: most of those
  ground faces only cover what lies in front of the face).
- **Not reproduced** as a face vanishing in the middle of the picture in a race. If it shows again on the board: the
  track, the POV and a shot, then key 2 and the serial log's `racer,pvs` lines name the faces. The flyby's yaw could be
  smoothed (a moving average of the line's yaw): every flyby pin would move, so not done here.
- **Test.** `racer_bugpass.mjs` 3: the oracle on the flyby of Salt, Neon and Glacier: no face lost, none dropped;
  `--break pvs` (key @: the PVS list thinned) is caught (13,894-17,582 faces lost a lap).

## 3. Cars overlap

- **Cause.** `update_contacts` does run in both models, but it is freds72's: only the PLAYER feels the others, only the
  first car within 2 units is looked at, the colliders are 0.25 + 0.312 units long, and the AI cars never see each
  other. The GT is drawn 2x that, and ARCADE draws it the track's car scale more (2.5 on our Kit tracks): the AI cars
  drove through each other and the player's colliders were a fifth of its drawn size.
- **Fix.** ARCADE only (`racer/pushes.zig`): every pair of cars on the same deck pushes, at the DRAWN size: a car is a row of
  three circles along its footprint (the model's shadow box times the car scale: `Car.body`, set by `Race.setModel`), as
  wide as the car; overlapping circles are moved apart by half the overlap each and a closing speed along the separation
  is exchanged (equal masses, 20 % bounce); the player's pushes count as contacts (the impact sound). CLASSIC is
  freds72's, untouched (its Lua CRCs unmoved). The cars are now pushed into the frame FAR TO NEAR (`carview.drawRace`):
  two cars on one ground face share its key, and a tie is drawn in push order (it was the car index).
- **Test.** `pushes_test.zig`: the body is the GT's footprint at Salt's scale, none in CLASSIC; two cars overlapping by half
  a width are apart and no longer closing after one tick; a 1,500-tick race on Salt keeps every pair under 1/8 of a half
  width of overlap, and `--break push` (key !: freds72's contacts in ARCADE) lets them overlap by more than half a width.

## 4. No engine sound

- **Checked on the PUBLIC cart** (no `-Dracer_music`): an ARCADE race keys the engine on FM 6 and moves its pitch with the
  revs (131 pitches driven, 61 more on the AI pilot), plays the skid noise and the impacts; a CLASSIC race too (115 / 28).
  The board's SD (read-only) holds the racer cards M1-M6 and the local 32X ones; the only one built with
  `-Dracer_music` (effects off by design) is RACER M3 MUSIC (build_racer_version.sh's `music`); the M5 / M6 32X cards and
  the feel cards (not on the SD) have the effects on. So "off by design" does not explain it (`racer_bugpass.mjs` 2, a fake BARD queue host; nothing
  checked an engine write before: racer_audio_check counted the countdown's beeps).
- **Two real faults fixed.** (a) A car on the AI pilot (key L) had a still engine note: `npc.control` drops steer's rpm;
  the ARCADE tick now keeps it itself (`arcadecar.steered`). (b) The effects' channels were asked for ONCE at the first
  frame: one refusal there (a queue not ready) silenced them for the whole session. `audio.zig` asks again once a second
  and logs `racer,audio,<device>,<owning>,<anchored>,<refused>` on a change: the board's serial log will say why it is silent.
- **Not checked on the board** (Matt was using it; read-only: it had rebooted, no racer log left). On the bug-pass card:
  a race with the serial log open; `racer,audio,1,1,0` means the channels are owned and nothing was refused.
- **Test.** `racer_bugpass.mjs` 2; `--break mute` (key h before the race) is caught.

## 5. An in-picture race HUD

- `racer/hudpic.zig`: our own HUD over the view, after the 3D and after the view's CRC (no plane: a plane costs ~0.6 Mc a
  frame): POS n/8, the clock, LAP n/3 and the lap time across the top; a rev gauge (12 rising segments, the last three red)
  and the speed in km/h at the bottom left; the course name at the bottom right; a bigger minimap (the line in white on a
  dark shadow, the AI cars in their liveries, the player in yellow) at the right; the countdown, EXTEND TIME and FINISH big
  in the middle. The look is the title's (the logo's scaled font, gradient and drop shadow), not the arcade's.
- **The bands stay as an option**: key 0 switches back to them; they always show on the grid, the results and the bench
  laps (their lines are the benchmark's); under the picture HUD they are blank. The 3D repaints the view every frame, so the
  overlay is redrawn every frame (runs of @memset, the map's points as single stores): +0.07 Mc mid-race on Salt.
- **Test.** `hudpic_test.zig` (a running ARCADE race's numbers, the overlay only in its places, the gauge: it caught a
  real wrap, `@min(rev, 256)` narrows to u9); `racer_bugpass.mjs` 4 (against key 0: every changed pixel in the HUD's
  places, the bands blank, the countdown's digit in the middle, CPU = AFFINE, pinned; `--break hud`).

## 6. Skids as smoke

- `racer/smoke.zig` replaces the skidmarks (`skid.zig` is gone): a sliding wheel of the player's car puffs every 2 ticks at
  its DRAWN place (the tyres placed in the model's footprint box, any car file's, times the car scale: the feel branch's
  unscaled points are fixed); a puff lives 16 ticks, grows (0.06 -> 0.16 units) and rises, drawn as a hexagon facing the camera
  (two trapezoids sharing their middle edge: no pixel lightened twice by one puff) that LIGHTENS what is under it one
  level up its ramp (`shadow.lightSpan`, the shadow's index trick the other way: real transparency, no dither; a ramp's
  top, the first 16 entries and the haze pool kept). Key 1 hides it (the harness' A/B).
- **Test.** `shadow_test.zig` (lighten for all 256 indices, word = byte, the span at any alignment, with a haze pool);
  `drive_test.zig` (the emission and the ring, a puff's two lightened halves on one key over its face's, the scaled
  tyre; `smoke_test.zig`); `racer_drive.mjs`: lap v1 against the same lap with the smoke hidden, every changed pixel is lighter in its own
  ramp (226 pixels two or three levels where puffs overlap). A puff behind the car (nearer the chase camera) veils the
  car's rear: it is drawn by its own depth, as smoke between the camera and the car is.

## 7. Far objects pop in too near

- **Cause.** The PVS' distance is DDA steps (a Manhattan distance): R 8 reaches 8 tiles straight ahead but ~5.7 on a
  diagonal, and R is at most 8 (the baked depth). Past it nothing is drawn; the flat ground is the far ground's colour, so
  what pops in is the TALL things (trees, buildings, hills).
- **Built: the far ring** (`frame.far`, key +: off, 2, 4 tiles): from the tiles the run-time DDA reaches between R and R + 2
  or 4 steps, only the faces at least 1 unit tall. Hills and buildings rise in earlier (a DXBAY shot shows the bay's hills
  on both sides that R 8 alone leaves out).
- **Measured** (frame_cost without the I$ term, plain twin, R 8; grid / mid-race): Salt Flats +0.22 / +0.30 Mc at ring 2,
  +0.26 / +0.34 at ring 4; DXBAY (local) +0.41 / +0.46 and +0.74 / +0.50. **Off by default**: our grids sit at the 60 fps
  edge and the 32X courses already run 25-33 fps; a haze has no palette room on the 32X courses; a per-track R above 8
  needs deeper baked lists and costs more than the ring. What would pay: fewer faces on the 32X courses (merging the
  coplanar strips in the importer), then the ring by default there.
- **Test.** `far_test.zig` (off adds nothing; on, only tall faces from tiles past R, more with a deeper ring).

## 8. The shadow follows the footprint

- `tools/racer/footprint.py`: the near model's top view (wheels, hull, cabin, wing) cut into slabs along z; each slab's
  covered x-intervals become a quad (a trapezoid from the intervals at the slab's two ends, a rectangle where they do not
  pair up), quads that continue each other merged; at most 16, non-overlapping (the fill rule gives a shared edge to one
  polygon), on the ground facing up. `carc.convert` writes it as the shadow of EVERY car it converts: our GT (5 quads: the
  body and the wheel arches) and the local 32X cars (the formula car: 12 quads, its wheels apart from its body). The cart
  reads 1..16 shadow faces (`carfile.zig`, `Model.foot` = their box: items 1 and 3) and draws them all, REAL (one ramp
  level down) or the checkerboard (key y) as before. The footprint lies under the car, as the 32X's: the visible part is
  its rim (221 shadow pixels at the grid, the old offset quad 567).
- **Test.** `test_racer_footprint.py` (no point under two quads, the wheels kept apart, facing up, merged, a car past 256
  vertices refused, the GT's wheels under its shadow), `carfile_test.zig` / `carmodel_test.zig` (several faces, the box,
  an empty shadow refused), `racer_car.mjs` (every shadowed pixel exactly one level down: no double darkening).

## Pins moved (and why)

- `racer_race.mjs`: lap v2's view CRC list (the footprint shadow, the cars keyed over their footprint and pushed far to
  near) and the crest pose (the footprint shadow).
  Physics CRCs, the result hash and the HUD band hashes unchanged (the harness presses 0: the bands).
- `racer_drive.mjs`: lap v1's view CRC list (smoke at the footprint's tyres for skidmarks, the footprint shadow). Its physics lines unchanged.
- `racer_feel.mjs`: the ARCADE result hash (every pair of cars pushes) and the grid view (the footprint shadow).
- `arcade_test.zig`: the ARCADE oval race CRC (pushes).
- New: `racer_bugpass.mjs`' HUD frame. Unchanged: racer_tracks, racer_headless, racer_haze, racer_zone, racer_front,
  racer_library, racer_carfile, racer_car (its checks, not a pin), racer_audio_check; every CLASSIC physics / Lua pin.

## Frame cost (frame_cost without the I$ term, plain twin, R 8, Salt Flats)

| | grid | mid-race |
|---|---|---|
| the feel branch (54c2abc3) | 2.00 | 2.21 |
| bug pass, HUD in the bands (key 0) | 2.19 | 2.20 |
| bug pass, the picture HUD (default) | 2.19 | 2.27 |
| + far ring 2 / 4 (key +) | 2.41 / 2.45 | 2.52 / 2.56 |

The grid's +0.19 Mc: 0.05 is the footprint key (A/B'd: key O); the rest is not A/B'd, the footprint shadows (5
polygons a car instead of 1, darkened under the whole car) are the likely bulk. Mid-race cells are not like-for-like between builds (frame_cost drops VBLs by cost).

## Keys added

`0` the HUD: picture / bands (`racer_race` / `racer_feel` press it: their pins are the bands'); `1` the tyre smoke hidden; `2` the visibility oracle; `+` the far ring (off, 2, 4); and the
harness' mutants `O` (decals: the centre face only), `!` (ARCADE contacts back to freds72's), `@` (the PVS thinned).

## The board (cards: `prototypes/cards/build_racer_bp.sh <rev>` then `install_racer_bp.sh`; run without an outer flock)

Public **RACER BUGPASS** (`tests/demo-racer_bp.zmd`) and LOCAL **RACER BUGPASS 32X** (`tests/demo-racer_bpx.zmd`: the 32X
courses and cars re-made with this branch's tools, the cars' shadows their footprints). To look at: a race on Salt and on a
32X course in each POV (the HUD, the shadows, smoke on a hard corner, cars pushing at the start); the engine note with the
serial log open (`racer,audio`); fps at the grid's near POV (the cell at the 60 fps edge); key + on a 32X course (fps, and
whether the hills read better).
