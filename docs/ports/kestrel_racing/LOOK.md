# Kestrel Racing: the 32X look (R82, 27 Nov)

Matt's 32X screenshots (32x-1..6: Big Forest, Acropolis, the course select) against our 32X courses after the bug pass:
a flat sky over the hills, no START / C.P. gantries, a flat blue sea, AI cars pushed off the narrow roads for good, 27-31
fps. Branch `feat/racer-32x-look` (from `feat/racer-bugpass`). Nothing from the 32X ROM, its decoded data or a shot of it
is in a committed file: the importer pieces are LOGIC (tables found by the shape of the code that reads them; those shapes
are bytes of the cartridge's code, so they live in the LOCAL, git-ignored `signatures.json` beside the dump, read through
`vr32x_import.py --signatures`, default `prototypes/racer_re/vr_local/32x/signatures.json`, an error naming the path when
it is missing: `tools/racer/vr32x_sigs.py`), their tests synthetic (synthetic shapes too); the decoded panoramas, objects and tracks live in the git-ignored `prototypes/racer_re/vr_local/32x/`.

## 1. Panoramas (`<TRACK>.PAN`; racer/panofile.zig, pano.zig, backdrop.zig; tools/racer/panc.py)

**The cart.** A track may come with a panorama FILE on the disk, `<TRACK>.PAN` (panofile.zig documents the layout):
a palette-indexed strip that wraps a full turn (256..1,024 texels, a power of two), an UPPER part stored whole and a
LOWER part (a sea, a plain) stored one period wide when its rows repeat across, its own colours (up to 64) on palette
entries it names, the row on the horizon, the texel straight ahead at yaw 0, an OPAQUE flag. When the track goes on show
the cart reads it (raw or ZX0-packed, depacked into the backdrop's buffer, which `pano.largest()` sizes at init to the
disk's largest: a disk without one costs nothing) and draws it instead of the mood's backdrop shape: two CHISEL AFFINE
ops (upper, lower), square texels (1.25 px each way at 1,024 a turn: the art keeps its aspect), sitting on the horizon
row (so it follows the pitch), scrolling with the yaw. An OPAQUE strip replaces the sky / far-ground fill rows it
covers. Every field and every texel is bounded; the entries must lie on the track's own ramps, off the car ramps, and no
face or decal of the track may use them (`clash`); a bad file is refused by name (`racer,pan,refused,<NAME>,<why>`, BAD
PAN in the select's refusals) and the mood's shape is drawn. Old files and disks are unchanged.

**The 32X courses (local).** The backdrop is the Mega Drive's plane B (the 32X pixels are in front: every course colour
has the through bit, index 0 shows the VDP): 128 x 32 cells, Kosinski-packed tiles + an Enigma nametable per course,
4 CRAM lines; hscroll = heading / 64, so 1,024 pixels are exactly one turn (`tools/racer/vr32x_pan.py`, `vr32x_mdpack.py`;
details in the local `pano/NOTES_pano.txt`). The strip is 1,024 x 224 with the horizon on row 88; we keep 80 rows above
and 72 from it (the cart's level horizon is row 100 of 12..188), the sea / plain below as the lower part (Big Forest,
Bay Bridge, Acropolis repeat every 8-128 texels; Highland and Sand Park do not: kept whole). Colours: 23-29 a course, cut
to 24 (the nearest pairs merged) on 3 reserved ramps (the course keeps 20 of its 23: area-weighted colour error 3.9-5.0
-> 4.7-5.8, `vr32x_report.txt`), ordered dark to light so a puff of smoke or a shadow over it steps to a lighter / darker
entry. Yaw: the 32X shows strip column `x - heading / 64` and its heading turns the same way as our camera's yaw with the
opposite sign, so the column straight ahead is 160 + yaw / 64: `u0` = 160, no mirror. Checked against 32x-5/6: on the
Acropolis grid the island stands ahead, its peak left of the road, as in the screenshots. The mood's sky is set to the
strip's top colour (a camera pitched up sees it over the strip). Files: 88-156 KB raw a course; cart RAM free with the
local disk 72 KB (>= the library's 64 KB reserve; 165 KB before: the strip buffer grows from 64 to 156 KB).
`vr32x_import.py --pano` writes `vr32x_<n>.pan`; the card adds them as `DX....PAN`.

**Our tracks** keep their mood's backdrop shapes: no panorama generator of ours was made (panc.py's `test_strip` is the
harness' synthetic strip, not art). A Track Kit panorama would be `panc.encode` on a painted strip plus `free_entries`.

**Cost** (frame_cost, CPU fill, R 8, the five courses' grid and mid-race): the panorama is about free: -0.01 to -0.07 Mc
cart a frame with the GT cars (the sky rows it covers are not filled; its two AFFINE ops are 0.01 Mc of blitter in the
model), within +-0.1 with the 32X cars (item 5's table, A against B). NOT measured: the blitter time of up to 176 rows of AFFINE on the board before the CPU path's `blitSync`
(frame_cost does not model CHISEL's own time); the board's OSD fps is the check.

**Open:** the sky colour of two courses differs from the screenshots (CRAM sky Acropolis (R2,G4,B7) vs ~(2,3,7) on the
shot; the emulator's colour, or another CRAM writer not found); camera pitch moves the strip with our horizon, not the
32X's vscroll rule (clamp(pitch, -8, 16) - 8).

## 2. Course objects (tools/racer/vr32x_objects.py, vr32x_geom.place)

The boats and the roadside flags were never missing: they are tile-model polygons and our import draws them (the
Acropolis grid shot shows both). What the 68000 places OUTSIDE the tile maps, each frame into the SH-2's display slots,
is decoded and imported (`--objects`): per course 3 GANTRIES (START on the grid, C.P. on the two split gates; 6 animated
sign models, the fully lit one kept) and the course LANDMARKS (Big Forest: a Ferris wheel and a swing-ship ride; Bay
Bridge: 4 striped barriers, a windmill, a tower; Highland: a spinning object; Acropolis and Sand Park: none), moving parts
in their rest pose: 3-9 objects, 69-176 faces a course, dual-sided props (never ground: nothing drives on a banner).
Units and yaw are FITTED (the START posts stand just outside the road on all five courses, the Ferris and windmill bases
on the ground), not read from the SH-2's transform: medium confidence; the START gantry looks centred on Acropolis (as on
32x-6) and offset toward the pit side on Bay Bridge, Highland and Sand Park (not checked against a shot). The banner text
colour (entry $79, dark red) is small: the colour choice weighs the objects' entries 50x, or it took an olive grass
shade. Not decoded: four animated flag marshals (their places do not match the grid: likely the podium).

## 3. Water

The 32X's sea pattern is the plane-B panorama's lower part (item 1): Bay Bridge and Acropolis now show it, wave texture
and all, to the horizon. The lakes made of faces already alternate between several palette entries in the ROM (Acropolis
$99-$9E, kept apart by the colour choice). `--water` (`vr32x_water.py`) adds a second tone on top: each level water face is
2-coloured over its edge neighbours, the alternate one ramp level darker (16-35 faces a course with lakes); no per-pixel
work, no dither. It is in the local card; drop it if it reads as noise beside the ROM's own alternation.

## 4. Stuck AI cars (racer/rescue.zig)

ARCADE only (CLASSIC is freds72's: its Lua CRCs unmoved): an AI car, or the player flown by the AI pilot, is put back on
the racing line one segment on, stopped (the hard crash's placement, `wall.putBack`), after 5 s with three or four wheels
off the asphalt, or 8 s without gaining a segment (pinned, or lost under Highland's deck). The race only ticks in its
race / finish states, so the grid and the countdown never count. `racer,rescues,<n>` with the results.

Measured (local, `prototypes/cards/racer_32x_race.mjs`: a 3-lap ARCADE race on the pilot, key L, the real 32X cars):
without the rescue DXHIGH had two cars off the road for 2,370 and 4,297 ticks and 5 DNFs; with it 8 rescues and 2 DNFs
(slow, not stuck: longest off run 150 = the threshold); on the four other courses nothing reaches the thresholds (cars
that leave the road find it again within 113 ticks): 0 rescues, the races unchanged. Open: DXHIGH's two DNFs.

Tests: `rescue_test.zig` (an AI car parked off the asphalt is put back after STUCK_TICKS and not before, one segment on, on
the line's middle; a car pinned on the road after STILL_TICKS; a short trip off the road and a car that keeps gaining are
not; CLASSIC never; `break_rescue` (the mutant, key % in the cart) leaves it there).

## 5. Fewer faces (the 32X courses at 27-31 fps)

**Measured first, then built what pays.**
- Merging coplanar same-colour neighbours into convex faces of at most 4 vertices: **0 merges possible** on any course.
  The 32X strips alternate colours on purpose (of 5,622 shared edges on Big Forest 4,738 join different colours; of the
  rest, 310 would make hexagons, 193 concave quads, 317 are not coplanar). Not built.
- Sub-pixel scenery (a prop under 1-4 pixels seen from anywhere on the line): at most 44 faces a course. Not built.
- Never front-facing faces (seen from every sampled eye on the drivable area): 117-633 a course (4-16 %), but a back face
  costs a dot product in collect, ~0.1 % of a frame. Not built.
- **Decals** (1,100-1,322 a course, 20-25 % of the faces drawn): with decals off (key d) the cart's frame is 0.3-0.7 Mc
  lighter on the DXFOREST / DXACRO grid. Built: the mood flag **DECAL_NEAR** (trk.zig, mood.py bit 1): a face keyed farther
  than 24 units (`frame.DECAL_KEY`) draws no decals (road markings past it are a pixel or two). Only a track with the flag
  changes (none of ours: every public pin unmoved); the 32X import sets it with `--near-decals`. `far_test.zig`: the
  polygons keyed nearer than the cut are the same with and without the flag, the dropped ones are only far faces'
  decals. Cost on the 32X courses: see the table below.

Cart Mc a frame (frame_cost's `cart` term: no I$ term), CPU fill, R 8, the real 32X cars, local disks; A = the bug pass'
import (no option), B = `--pano --water`, C = B + `--objects --near-decals` (the card's):

| course | grid A / B / C | mid-race A / B / C |
|---|---|---|
| DXFOREST | 3.39 / 3.32 / 3.14 | 3.29 / 3.22 / 3.03 |
| DXBAY | 2.79 / 2.87 / 2.76 | 3.14 / 3.07 / 3.07 |
| DXACRO | 3.20 / 3.30 / 3.19 | 2.42 / 2.36 / 2.29 |
| DXHIGH | 3.23 / 3.34 / 3.18 | 3.47 / 3.49 / 3.36 |
| DXSAND | 2.88 / 2.97 / 2.81 | 2.85 / 2.78 / 2.73 |

DECAL_NEAR takes 0.1-0.2 Mc and pays for the gantries and landmarks it adds (69-176 faces); the whole look pass ends a
little lighter than the bug pass (-0.01 to -0.26). Not the 60 fps: the rest is the 32X's 4-5 k faces' transform and
fill, which no import-side cut found here reaches (with decals off entirely, key d: -0.3 to -0.7). The far ring (key +)
stays off.

## Keys added

`%` no stuck-car rescue (the A/B), `^` the panorama's CRC not checked (racer_look.mjs `--break crc`).

## Gate

`racer_look.mjs` + `--break crc` (two lines in build.sh): our synthetic test strip as `SALT.PAN` (no 32X data): drawn only
where the backdrop was (the faces over it untouched), CPU = AFFINE, pinned; a corrupted one refused (BadCrc), the mood's
shape drawn byte for byte. Native: `panofile_test.zig` (every refusal: magic, version, CRC, length, size, colours on the
car ramps or the fixed entries, a texel off its entries, OPAQUE with a clear texel, a clash with Salt's faces),
`rescue_test.zig`, `far_test.zig` (DECAL_NEAR). Python: `test_racer_panc.py`, `test_racer_vr32x_pan.py`,
`test_racer_vr32x_objects.py`, `test_racer_vr32x_water.py`, `test_racer_vr32x.py` (place). Pins moved: none.

## Not done

Item 6 (the course select's preview as a small 3D overhead render, 32x-3/4): not started.

## The board (cards: `prototypes/cards/build_racer_look.sh <rev>` then `install_racer_look.sh`; no outer flock)

Public **RACER LOOK** (`tests/demo-racer_look.zmd`: nothing changes in look on our tracks; the rescue in ARCADE races) and
LOCAL **RACER LOOK 32X** (`tests/demo-racer_lookx.zmd`: the 32X courses with their panoramas, gantries and landmarks, the
water tones, DECAL_NEAR, the real cars). To look at: each 32X course's grid against 32x-5/6 and 32x-1 (the island, the
clouds, START), turning (the strip must move with the hills), fps at the grid and mid-race against the bug-pass card,
and whether the far road markings are missed.
