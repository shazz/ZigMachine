# Kestrel Racing Track Kit: the manual (R82 M7)

The Track Kit lets you build a track (and a car) for Kestrel Racing in Blender, check it against what the cart can hold
while you work, and turn it into the files the cart loads: `NAME.KTR` (a track), `NAME.KCR` (a car), `NAME.PAN` (a
panorama). This manual covers the packaged add-on (version 1.1.0, Blender 5.3), the sample track, the conventions, the
budget meter, every error message and its fix, the look (mood, haze, scale, clock, draw distance, panorama), car files,
testing in the browser and putting tracks on the SD card.

The tables marked "generated" are written from the code by `tools/racer/kit_manual.py --write`; a gate test
(`tools/tests/test_racer_kit_manual.py`) fails when they drift, and when a message in the code has no line here.

## 1. Install

**The add-on zip.** From a checkout of the repository:

```
python3 -I tools/racer/kit_pack.py -o dist/            # dist/kestrel_track_kit-1.1.0.zip (about 50 KB)
python3 -I tools/racer/kit_pack.py -o dist/ --sample   # + dist/kestrel_oval.blend, the sample track (needs Blender)
```

The zip is a Blender 5.x extension: `blender_manifest.toml`, a thin `__init__.py`, and the add-on's Python unchanged
(`racer/blender/` plus every module it imports: the export, the budget meter, the converter, the bake, the AI cues, the
mood, the Car Kit). It needs nothing else: no repository, no pip.

- In Blender: Edit > Preferences > Get Extensions > the drop-down (top right) > **Install from Disk...**, pick the zip,
  and make sure "Kestrel Racing Track Kit" is ticked.
- Headless (what the gate does):
  `blender -b --command extension install-file -r user_default -e kestrel_track_kit-1.1.0.zip`.

Press **N** in the 3D view: the **Track Kit** tab holds three panels: *Track Kit budget*, *Track Kit mood* and *Car Kit
budget*.

**From the repository instead** (for Kit development): in Blender's Python console,
`import sys; sys.path.insert(0, "/path/to/ZigMachine/tools"); import racer.blender as k; k.register()`.

## 2. The sample: Kestrel Oval

`tools/racer/tracks/sample_oval_build.py` builds the sample as a Blender scene (it is generated, not a binary in the
repository; `kit_pack.py --sample` or `... --blend kestrel_oval.blend` keeps one). Open it and look at each part: it uses
every convention once.

| object | what it shows |
|---|---|
| `track` | the road strip: `TRACK_FACE` asphalt in two alternating materials, `GROUND_FACE` verges, `BORDER1` wall edges, the barriers (walls, double-sided), the racing line groups `TRACK_L` / `TRACK_R` / `LINE_START`, `CHECKPT_1..4`, and `CAM_NEAR` on the six segments under the pit gantry |
| `decals` | `DETAIL_FACE` decals: centre dashes, red and white kerbs on both turns, the start line |
| `gantry` | the pit gantry over the back straight (scenery, a double-sided material seen from below) |
| `scenery` | a grandstand, infield trees, tyre stacks (`PROP_FACE`) |
| `start_grid` | the 8 grid slots, empties parented to it, facing the travel direction (their local +Y) |
| the scene | every mood property: sun, sky, the hills backdrop, a haze, a set race clock (90 s + 15 s), a draw distance cap (7), the world and car scales |

Two 120-unit straights, two turns of radius 32, 96 segments: 631 faces with their decals, 897 vertices, 16 colour ramps of
23. The gate converts its export end to end (export -> converter -> `SAMPLE.KTR` -> the cart loads it from C:\RACER\ in
node: `apps/harness/racer_kit.mjs`), and installs the zip into an empty Blender user directory and exports the sample
through the installed add-on (`tools/tests/test_racer_kit_pack.py`).

## 3. Conventions

Blender is Z-up; the cart is y-up. The exporter maps (x, y, z) to (x, z, y). The world is 32 x 32 tiles of 8 units,
centred on the origin: keep everything within +-128 units in X and Y. A Kit track is authored at about a metre a unit
(roads 10-12 units wide).

**Vertex groups.** A face belongs to a group when ALL its vertices do; the first match in this order wins:

| group | the face is |
|---|---|
| `DETAIL_FACE` | a decal: drawn on the ground face under it (coplanar, inside ONE ground face's edges within 0.02 units) |
| `TRACK_FACE` | asphalt: drivable |
| `GROUND_FACE` | off-road: drivable |
| `PROP_FACE` | scenery |
| (none) | a wall |

- `BORDER1`, `BORDER2`, `BORDER3` (any `BORDER*` group): an edge of a ground face whose two vertices share one is a wall
  edge for the physics. A ground face holds at most 3.
- **The racing line.** `TRACK_L` / `TRACK_R`: the road's left and right edge loops (each one closed loop of edges; every
  left vertex joined by one edge to one right vertex). `LINE_START`: the one left vertex of segment 0. The line runs the
  way grid slot 0 faces.
- **Checkpoints.** `CHECKPT_1..n`: one left vertex each, in lap order; the checkpoint is the segment that ends there, so
  the last one is the start line. The sample has 4.
- **Camera zones.** `CAM_NEAR`: left vertices whose segment (to the next vertex) runs under a roof: there the far chase
  camera blends to the near one (a tunnel, a gantry, a warehouse).
- **The start grid.** Exactly 8 objects (empties) parented to an object named `start_grid`, sorted by name, facing their
  local +Y.
- **Materials.** A material is a colour ramp (its name is the ramp's). The custom property `ktrk_rgb = [r, g, b]`
  (0..255) is the colour of a face square to the sun; `ktrk_dual = 1` makes it double-sided. Faces have NO lighting at run
  time: each face's tone is baked from its normal against the track's fixed sun, at most three levels (~27 %) darker
  turned away. Neighbouring road panels alternate between two close materials (authored, as `asphalt_a` / `asphalt_b`).
- **The far ground.** `ktrk_far_ground` names the material the ground beyond the draw distance shows. **Tick its Fake
  User** (the shield in the material list) if no face uses it: Blender drops an unused material when the file is saved.
- **Winding.** Faces are wound counter-clockwise seen from outside (Blender's normal points out). Drivable faces must point
  up and be convex seen from above; quads must be planar (split a bent quad into two triangles). Faces are 3 or 4 vertices.
- **AI cues.** Nothing to author: the converter bakes each segment's AI speed from the line's curvature.

## 4. The budget meter

The *Track Kit budget* panel recounts after every edit (and on its refresh button) and shows one row per limit, red when
over, then the converter's refusals. **HARD**: the cart cannot hold it; the converter refuses. **SOFT**: over our frame
budget (60 fps on the board at the bench R); the converter refuses too, so stay under. The "busiest tile" row names the
tile: the cart draws a tile's faces together, so spread dense scenery out.

Generated (`budget.rows`, `tools/racer/limits.py`):

<!-- gen:budget -->
| row | limit | kind |
|---|---|---|
| faces in the busiest tile | 64 | SOFT |
| faces (with decals) | 3,000 | SOFT |
| vertices | 8,192 | SOFT |
| colour ramps | 23 | HARD |
| racing-line segments | 256 | HARD |
| start grid slots | exactly 8 | HARD |
| checkpoints | strictly ascending | HARD |
| a face (or a decal) with no area | none | HARD |
| the priced frame at R 5 (the converter's walk) | 1.55 Mc | SOFT |
<!-- /gen:budget -->

How to get back under: merge materials of close colours (ramps); fewer, longer segments on straights (segments); fewer
props or simpler props in the busiest tile (tile faces); triangles only where they are needed (faces, vertices).

## 5. The look: the mood panel

The *Track Kit mood* panel shows every `ktrk_*` scene property as a row (a value the converter would refuse in red) and
**Add mood properties** fills in the missing ones at their defaults (the defaults are what the export uses when a
property is absent, so adding them changes nothing). Generated (`tools/racer/mood_props.py`):

<!-- gen:mood -->
| property | panel row | default | meaning |
|---|---|---|---|
| `ktrk_name` | Name | (the scene name) | the track's name (24 characters on the cart); unset: the scene's name, as the export |
| `ktrk_mood` | Mood | noon | a name for the look |
| `ktrk_sun` | Sun | (0.0, 0.0, 1.0) | the baked light's direction, Blender axes (Z up) |
| `ktrk_far_ground` | Far ground | (none) | the material the ground beyond the draw distance shows |
| `ktrk_sky` | Sky top, horizon | [28, 60, 150, 170, 205, 235] | 2 x RGB: the copper's gradient |
| `ktrk_hills` | Backdrop far, near, top | [110, 130, 170, 70, 100, 90, 60, 60, 90] | 3 x RGB: the panorama strip |
| `ktrk_backdrop` | Backdrop shape | hills | one of hills, docks, peaks |
| `ktrk_clock` | Race clock start, extension | [0, 0] | seconds; 0 = computed (max 250, 60) |
| `ktrk_draw_r` | Draw distance cap | 0 | tiles 3..8; 0 = none (the player's) |
| `ktrk_haze` | Haze colour | [0, 0, 0] | RGB: what far faces blend toward (M6; usually the sky's horizon) |
| `ktrk_haze_start` | Haze start | 0 | x/256 of the draw distance: nearer faces are untouched |
| `ktrk_haze_strength` | Haze strength | 0 | x/255: the blend at the draw distance; 0 = no haze |
| `ktrk_world` | World scale | 1067 | Q8: the ground's speed x freds72's at the same km/h (64..4096) |
| `ktrk_car` | Car scale | 640 | Q8: the car drawn x the GT's size (64..4096) |
<!-- /gen:mood -->

- **The haze** (M6) blends far faces toward the haze colour by distance band; it needs a spare palette entry per distinct
  face colour (fewer materials leave more room). Usually the haze colour is the sky's horizon.
- **The scales** (FEEL.md): a Kit track at a metre a unit moves the ground 1067/256 times freds72's at the same km/h and
  draws the car 640/256 times the GT; change them only for a track authored at another size.
- **The clock** 0, 0 lets the cart compute it from the lap length; set it for a track whose computed clock feels wrong.
- **The draw distance cap** lowers the player's R (default 8) on a track too heavy for the board at R 8.
- **A panorama** (`<TRACK>.PAN`, LOOK.md) replaces the backdrop shape with a strip that wraps a full turn, on palette
  entries the track's faces do not use. `tools/racer/panc.py` writes them (`panc.encode` from your own strip; its command
  line makes the synthetic test strip on a track's free entries). The cart reads a panorama from **its own disk only**: it
  goes in a track pack disk (section 9), not in C:\RACER\.

## 6. Exporting

The budget panel has two buttons: **Export .ktrk.json** (the neutral document, for the repository's tools) and **Export
.KTR (cart)** (the cart's file, converted inside Blender: the same budget check and refusals). Without Blender:

```
python3 -I tools/racer/trackc.py mytrack.ktrk.json -o MYTRACK.KTR
```

Name it 8.3: up to 8 of A-Z 0-9 _, then `.KTR`. The stem is the name the track select shows.

## 7. Car files (the Car Kit)

One mesh object per part: `car_wheels`, `car_hull`, `car_cabin`, `car_wing` (the near model), `car_shadow` (one quad on the
ground), `car_lod1` (the far model, about 12 faces). Materials: `body` and `stripe` (they take the livery), `dark`, `glass`,
`rim`, `head`, `tail`, `shadow`. Scene properties `kcar_name`, `kcar_sun`. The *Car Kit budget* panel meters it;
**Export .KCR (cart)** writes the cart's file (its Scale: the size the car is drawn, as `carc.py --scale`; the GT is 2).
`tools/racer/carc.py` does the same from a `.kcar.json`, and `carc.pack_set` makes a set (up to 5 cars and their own 7
colours: model 0 the player's, the rest the AI's).

The cart looks for `<TRACK>.KCR` (that track's cars), then `CAR.KCR` (every track's), on its disk and in C:\RACER\, then
draws the built-in GT. A refused file falls through to the next.

## 8. Testing in the browser

Make a track pack disk (section 9) and drop it on the machine page (the "run your own cart" picker or a drop on the
page: it boots the racer cart with your files; nothing leaves the browser), or serve it and open `?disk=<url>`. A C:
image is `?c=<url>` (a FAT image with `HD/RACER/`). Press `t` (or open the track select) and look for your track; a
refused file shows its reason in the select's refusals and in the console (`racer,track,refused,<NAME>,<why>`).

## 9. Track packs and the SD card

`tools/racer/trackpack.py` takes files or folders of `.KTR` / `.KCR` / `.PAN` and checks each one with the cart's own rules
(Python twins of the cart's parsers: `tools/racer/twin_trk.py`, `twin_files.py`), so a file is refused here for the reason
the cart would give, by the same name:

```
python3 -I tools/racer/trackpack.py MYTRACKS/ --zmd racer-pack.zmd --title "MY PACK"   # a disk: the racer cart + the files
python3 -I tools/racer/trackpack.py MYTRACKS/ --hd SDCARD/                            # SDCARD/HD/RACER/<files>
```

- **On the SD card**: the cart's `C:\RACER\` is the card's `/HD/RACER/`. Copy `.KTR` and `.KCR` files there; they are listed
  after the disk's tracks. Panoramas are refused in an `--hd` pack (the cart reads them from its disk only).
- **A pack disk** carries the racer cart and the files (up to 23); put it on the card's shelf like any disk.
- At most 15 tracks besides the built-in oval (disk and C: together); a track over 1 MiB depacked, 25,600 vertices or
  10,240 faces is refused; the cart's RAM holds the largest track listed (it drops the largest when it cannot).
- ZX0-packed files (`zig-out/bin/zx0pack`) load faster; the `--zmd` pack packs raw files when zx0pack is built.

## 10. Every error and its fix

Generated (`tools/racer/kit_errors.py`, `kit_errors_car.py`; `...` is the part the message fills in):

<!-- gen:errors -->
**Export (the add-on's Export buttons, the live meter)** (`tools/racer/kit_export.py`)

| message | fix |
|---|---|
| `face ...: a DETAIL_FACE lies on no ground face` | a decal must lie flat on a TRACK_FACE or GROUND_FACE face (within 0.02 units of its edges): snap it onto the road |
| `face ...: the engine's normal disagrees with Blender's (winding)` | a scenery or wall face whose corners do not agree with its normal (bent or concave): flatten it or split it in triangles |
| `TRACK_L is not one closed edge loop (... vertices without exactly two neighbours)` | TRACK_L must be one closed loop of edges round the track: every vertex in it joined to exactly two others in it |
| `LINE_START must hold exactly one TRACK_L vertex, and the start grid must exist` | put the start line's left vertex (and only it) in LINE_START, and parent the 8 grid empties to `start_grid` |
| `face ...: material ... has no ktrk_rgb` | give the material the custom property ktrk_rgb = [r, g, b] (0..255), or put the face on a material that has it |
| `TRACK_L vertex ...: ... TRACK_R vertices joined to it by an edge, want 1` | every left-edge vertex needs exactly one edge across the road to a TRACK_R vertex: the road is a strip of quads |
| `... must hold exactly one TRACK_L vertex` | a CHECKPT_n group holds one left-edge vertex: the checkpoint is the segment ending there |

**Reading an export** (`tools/racer/ktrk.py`)

| message | fix |
|---|---|
| `not a ktrk-json v1 document` | the file is not a Track Kit export: re-export it with the add-on |

**Validation (the converter's first stage)** (`tools/racer/ktrk_check.py`)

| message | fix |
|---|---|
| `...: needs 3-4 valid vertex ids` | the cart draws triangles and quads only: triangulate or split n-gons |
| `...: unknown kind ...` | a hand-edited document: a face kind is track, ground, wall or prop |
| `...: ground normal does not point up` | a TRACK_FACE / GROUND_FACE face is upside down: flip its normal (Mesh > Normals > Flip) |
| `racing line needs at least 3 segments` | the TRACK_L / TRACK_R loops are too short: the line needs 3 segments or more |
| `racing line: vertex id out of range` | a hand-edited document: re-export it |
| `...: not planar within ...` | a quad bends: flatten it, or split it into two triangles (banked roads change the bank slowly) |
| `...: wound against the physics' inside test` | a drivable face must be convex seen from above (the physics' inside test): split it |
| `...: more than 3 borders` | a ground face holds at most 3 BORDER edges: split the face |
| `checkpoint ... outside the line` | a hand-edited document: re-export it |
| `start grid is empty` | parent the 8 grid empties to an object named `start_grid` |
| `... vertices outside the ...x... tile world` | the world is 32 x 32 tiles of 8 units, centred on the origin: +-128 units in X and Y |
| `...: border ... faces outward` | a BORDER edge must face into its face: check the face's winding |
| `face ... inner ...: not coplanar with its parent` | a decal must lie on its ground face's plane: snap it down |
| `face ... inner ...: outside its parent's edges` | a decal must sit inside ONE ground face: cut it where it crosses a face edge |

**The budget check** (`tools/racer/budget.py`)

| message | fix |
|---|---|
| `... limit: ... ... > ......` | a meter row over its limit. HARD: the cart cannot hold it (merge materials, fewer segments). SOFT: over our frame budget (fewer faces in the busiest tile named, fewer faces or vertices) |
| `HARD limit: start grid has ... slots, the race needs ...` | parent exactly 8 empties to the `start_grid` object |
| `HARD limit: checkpoints ... must ascend strictly (the cart refuses the track at init)` | number CHECKPT_1..n in lap order from LINE_START, the last one at the start line |
| `HARD limit: face ...... has no area (no normal)` | a face (or a decal) of zero area: merge its vertices away (Mesh > Clean Up) |

**Conversion (palette, mood, cues, haze)** (`tools/racer/kit.py`)

| message | fix |
|---|---|
| `palette ...: want [r, g, b] ints 0..255, got ...` | ktrk_rgb must be three integers 0..255 |
| `materials ... have no palette colour` | these materials are used by faces but have no ktrk_rgb |
| `far_ground ... is not in the palette` | ktrk_far_ground must name a material with ktrk_rgb. Blender drops a material no face uses when the file is saved: tick its Fake User (the shield) in the material list |
| `HARD limit: ... colour ramps > ...` | each material is a ramp: merge materials of close colours (23 at most, the far ground included) |
| `mood sun ...: want [x, y, z] with y > 0 (above the horizon)` | ktrk_sun is a direction with a positive Z in Blender (above) |
| `mood ... ...: want ... x [r, g, b] flattened (... ints)` | ktrk_sky is 6 numbers (top, horizon), ktrk_hills 9 (far, near, top) |
| `mood backdrop ...: one of ...` | ktrk_backdrop is hills, docks or peaks |
| `mood clock ...: want [start, extension] in seconds (0 = computed)` | ktrk_clock is two integers, or [0, 0] for the computed clock |
| `mood draw_r ...: the draw distance cap in tiles (0 = none)` | ktrk_draw_r is an integer: 0, or 3..8 |
| `mood world ... / car ...: Q8 ints ........` | ktrk_world / ktrk_car are integers 64..4096 (256 = 1x) |
| `mood haze start ... / strength ...: ints 0..255 / 1..255` | ktrk_haze_start 0..255, ktrk_haze_strength 1..255 (0 = no haze) |
| `mood haze: ... face colours, the palette has ... spare entries (the cart's haze pool)` | the haze needs a spare palette entry per distinct face colour: fewer materials, or no haze |
| `an authored track needs ... (see tools/racer/kit.py)` | a hand-made document lacks palette, mood or far_ground: export it with the add-on |

**The track writer** (`tools/racer/trackc.py`)

| message | fix |
|---|---|
| `material ... has no palette ramp` | a face's material is not in the palette: give it ktrk_rgb |
| `border edges ... must be ascending and inside the face` | a hand-edited document: re-export it |
| `racing line ...: cue ... is not 0..255` | a hand-edited document: the AI cues are baked by the converter |
| `mood ground ramp ... is past the palette's ... ramps` | a hand-edited document: re-export it |

**The mood block** (`tools/racer/mood.py`)

| message | fix |
|---|---|
| `mood world ... / car ...: Q8 ........` | ktrk_world / ktrk_car: 64..4096 |
| `mood ...: level 0..7, backdrop < ..., flags ... only` | a hand-edited document: re-export it |
| `mood clock ...: start 0..... s, extension 0..... s` | ktrk_clock: a start of at most 250 s, an extension of at most 60 s |
| `mood draw distance cap ...: 0 (none) or ........ tiles` | ktrk_draw_r: 0, or 3..8 |
| `mood colours ..., haze start ..., strength ...: ints 0..255` | every colour channel and haze number is 0..255 |
| `mood haze ... start ... without a strength (0 = no haze)` | set ktrk_haze_strength, or clear ktrk_haze and ktrk_haze_start |

**The mood panel (red rows)** (`tools/racer/mood_props.py`)

| message | fix |
|---|---|
| `backdrop ...: one of ...` | hills, docks or peaks |
| `draw_r ...: 0 or ........` | 0 (none) or 3..8 tiles |
| `... ...: ........ (Q8)` | the world / car scale: 64..4096, 256 = 1x |
| `... ...: 0..255` | the haze start / strength: 0..255 |
| `...: ... numbers` | sky 6, hills 9, clock 2, sun 3, haze 3 numbers |
| `clock: start 0....., extension 0.....` | start 0..250 s, extension 0..60 s |
| `...: 0..255 each` | colour channels are 0..255 |

**Car Kit export** (`tools/racer/kcar_export.py`)

| message | fix |
|---|---|
| `object ...: no car part ... (one of ...)` | name each car mesh car_wheels, car_hull, car_cabin, car_wing, car_shadow or car_lod1 |
| `... face ...: the engine's normal disagrees with Blender's (winding)` | a bent or concave car face: flatten it or split it |
| `not a ... v... document` | the file is not a Car Kit export: re-export it with the add-on |

**Car Kit budget and shape** (`tools/racer/carcheck.py`)

| message | fix |
|---|---|
| `HARD limit: ...: material ... is not a car material (...)` | use body, stripe, dark, glass, rim, head, tail or shadow |
| `HARD limit: ...: a fixed colour needs a ramp 12..18 and a level 0..7` | a `fixed` face names its ramp (12..18) and level (0..7) |
| `HARD limit: ... has ... vertices (a face record holds 3 or 4)` | triangulate n-gons on the car |
| `HARD limit: ...: a vertex id is past the ... vertices` | a hand-edited document: re-export it |
| `HARD limit: ... has no area (no normal)` | merge the degenerate face's vertices away |
| `HARD limit: the shadow part must be exactly one quad of material shadow (the cart darkens one quad a car)` | car_shadow is one quad on the ground, material shadow |
| `HARD limit: the shadow quad must lie flat on the ground (y ........ Q7)` | put the shadow quad at the car's ground level |
| `HARD limit: part ... is missing (the cart draws ...)` | every car needs car_hull and car_lod1 (and its shadow) |
| `... limit: ... ... > ...` | a car meter row over its limit: fewer faces or vertices (the far model: 12 faces) |
| `HARD limit: ... is not planar (the 4th vertex is off the others' plane)` | flatten the quad or split it |
| `HARD limit: ... is not convex (the fill draws convex polygons)` | split the concave face |
| `HARD limit: material shadow is only for the shadow part (...)` | give the face another car material |
| `SOFT limit: the car is ........ on ..., the envelope is ........ (Q7)` | the car is bigger than the cart's car envelope: scale it down (or let carc.py --scale size it) |
| `HARD limit: no car part ...` | add the missing car_<part> object |

**The car writer** (`tools/racer/carc.py`)

| message | fix |
|---|---|
| `the footprint takes the car past ... vertices` | the shadow footprint adds vertices: fewer vertices on the hull |
| `a set holds 1..... models and ... ramp colours` | a car set file holds 1..5 cars and a palette of 7 colours |

**The panorama writer** (`tools/racer/panc.py`)

| message | fix |
|---|---|
| `no ... free entries on the track's ... ramps` | the track's ramps have too few unused entries: fewer track materials, or fewer strip colours |
| `... rows do not fit ... upper + ... lower rows` | the strip is too tall: at most 128 rows above the horizon split, 160 below |
| `a ... x ... strip (... texels, u0 ...): width a power of two 256..1024` | the strip's width is 256, 512 or 1024 texels a full turn |
| `entries ........: off the fixed entries, the car ramps and 255` | choose entries on the track's own ramps (panc picks them for you) |

**The track pack builder** (`tools/racer/trackpack.py`)

| message | fix |
|---|---|
| `... tracks: the cart lists ... besides its oval` | split the pack: at most 15 tracks (disk and C: together) |
| `no .KTR in the pack` | a disk pack needs a track |
| `...: no ....KTR here: it is used only when a track of that name is on show` | a warning: a car file named for no track here |
| `no ...: build the cart first (./build.sh --fast)` | the disk pack carries the racer cart: build it, or give --cart |
| `...: not an 8.3 name of A-Z 0-9 _ ending .KTR, .KCR or .PAN` | rename the file: up to 8 letters, digits or _, then .KTR / .KCR / .PAN |
| `...: twice in the pack` | two files with one name (case does not count): keep one |
| `... files: a disk's FAT holds 23 besides the cart` | split the pack over two disks |
| `...: refused (...)` | the file is ZX0-packed but its stream is broken: pack it again (zx0pack) or give the raw file |
| `...: the cart reads a panorama from its own disk only: put it in a --zmd pack` | panoramas go on a disk pack, not C: |
| `...: no ....KTR in the pack (a panorama is checked against its track's palette)` | add the panorama's track to the pack |
| `...: the cart refuses it (...)` | the cart's reason, below (the same name the cart logs) |

**The cart** (its console `racer,track,refused,<NAME>,<why>` / `racer,car,refused` / `racer,pan,refused`, the select screen's refusals; the pack builder names the same)

| reason | what it means, what to do |
|---|---|
| `Truncated` | the file is shorter than its header says (a copy cut short): copy it again |
| `BadMagic` | not a Kestrel Racing file of that kind (.KTR a track, .KCR a car, .PAN a panorama) |
| `BadVersion` | written by another version of the converter: convert it again with this Track Kit |
| `BadCrc` | the bytes changed after the converter wrote them (a bad copy, a hand edit): convert or copy it again |
| `BadBlock` | a count or offset in the header points outside the file: convert it again |
| `BadMood` | the mood block is out of range (the draw distance cap 0 or 3..8, the clock, the haze): fix the mood and convert |
| `BadPack` | a ZX0-packed file whose stream is broken: pack it again |
| `ReadFailed` | the disk or the card could not read the file: check the card |
| `TooBig` | over the cart's buffers (a track over 25,600 vertices or 10,240 faces, a car file over 32 KB) |
| `BadFace` | a car face with more than 4 vertices, a vertex past the model, or a decal: convert the car again |
| `BadParts` | a car's parts are out of order or missing (a hull, a far model, 1..16 shadow faces): convert the car again |
| `BadSize` | a panorama's width (256..1024, a power of two), rows or horizon are out of range |
| `BadColours` | a panorama's colours are off the palette or over the car ramps (12..18) |
| `BadTexel` | a panorama texel uses a colour the strip does not own |
| `Clash` | the panorama's entries are not on its track's ramps, or a face of the track uses them: make it with panc for THIS track |
| `not_track` | the scan: the file's first bytes are no track (magic, version, size): the select shows INVALID |
| `too_big` | the scan: over the 1 MiB track buffer once depacked: TOO BIG |
| `no_ram` | the scan: the cart's RAM cannot hold the largest track listed: NO RAM (the largest file is dropped) |
| `bad_car` | a car file was refused (the reason is in the console): the built-in GT is drawn, BAD CAR |
| `bad_pan` | a panorama was refused (the reason is in the console): the mood's backdrop shape is drawn, BAD PAN |
<!-- /gen:errors -->

## 11. Licence (pending)

**The Track Kit's licence is not decided: it is Matt's decision (PORT_PLAN Q2).** Until then the zip's manifest carries the
placeholder `SPDX:LicenseRef-Pending`, and the add-on's older source headers ("ours, MIT") are not a decision. The options:
**MIT** for the kit's code, like freds72's engine (`pvs_bake.py` follows his engine and keeps his MIT notice whichever is
chosen); **CC-BY** for the sample track and its export, which are content, not code (with the code under MIT); or
**proprietary** (shipped with the cart, no redistribution). One constraint for all three: Blender's position is that an
add-on, which imports `bpy`, falls under Blender's GPL, so the CODE needs a GPL-compatible licence (MIT is; a proprietary
add-on is not); tracks and cars made with the kit are the author's content either way.

## 12. What is not here yet

- **No screenshots of the panels**: headless Blender (`-b`) draws no interface. The panels' rows are the generated
  tables above; Matt checks the panels in a GUI session.
- **No image-to-panorama importer**: `panc.encode` takes a palette-indexed strip; its command line only writes the test strip.
- **The zip is built from the repository**; where it is published for authors is open (with the licence).
