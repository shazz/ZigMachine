# SKYSTRIKE levels: the data model, and editing missions in Tiled

SKYSTRIKE (cart 79, `apps/zig/scenes/skystrike/`) keeps its missions in two files
from the game disk. `tools/skystrike/levels.py` turns them into Tiled JSON maps, one
per mission, and turns the maps back into the files byte for byte. The committed maps
are in `apps/zig/assets/screens/skystrike/levels/`. A disk that carries its own
`MISSIONS.DAT` / `SCRNDATA.DAT` is played instead of the cart's built-in set, so a
custom campaign needs no rebuild.

Line numbers below are the listing's (`prototypes/skystrike_re/SKYSTRKE.LST`, the
detokenised `SKYSTRKE.BAS`).

## 1. What defines a level (verified against the listing and the port)

A "level" is two things: **one world**, shared by every mission of a game, and **a
mission record**. Everything else is code, or random at run time.

### The world: `SCRNDATA.DAT`, 51 bytes

- Line 2500 (a new game) BLOADs it into bank 6 past the picture:
  `sc9 = start(6) + 32033`. There is one byte per screen of a strip of 51 screens
  (`sx` 0-50; flying off one end wraps to the other, 56-57). The byte is the **screen type**.
- It is loaded **once per game**, not per mission. Every mission of that game flies
  over the same world, and damage carries over (craters, destroyed buildings, sunk
  ships and captured bases persist).
- The type chooses the drawing routine at 1004-1005. Types 0-17 use `ON type+1 GOSUB`
  with 18 targets. Types 20-35 are "scene" `type - 20`, built from bank 8
  (`SKYSCRNS.MBK` = `screens.bnk`), at 1070/1900.
  - Bank 8 is a table of blocks (`s*160 + a*8`: source screen, source box, x, y,
    repeat; +80 is the damaged version).
  - The **art** is in `SKYPIC1.PAC` / `SKYPIC2.PAC` (banks 5 and 6), not in
    `SKYSCRNS.MBK`.
  - Types 18, 19 and 36+ draw nothing and set no ground zone.

| type | screen | type | screen |
|---|---|---|---|
| 0 | grass (see *random*) | 20 | houses |
| 1 | airfield | 21 | inn |
| 2, 3 | battleship, west / east half | 22 | gun and bunker |
| 4-7 | grass, never randomised | 23 | manor |
| 8 | bridge over a river | 24 | factory |
| 9 | sea | 25 | orchard |
| 10, 11 | sea, beach to the west / east | 26 | gun post |
| 12, 13 | aircraft carrier, west / east half | 27 | filling station |
| 14, 15 | cliff, sea to the east / west | 28 | barracks |
| 16, 17 | hill, rising / falling | 29 | silos |
| | | 30 | church |
| | | 31 | stream |
| | | 32 | fort |
| | | 33 | gun tower |
| | | 34 | coastal gun on a cliff |
| | | 35 | bunker in a hill |

The tileset `levels/skystrike_screens.png` is these screens as **the cart draws
them**. `tools/skystrike/render_tileset.mjs` runs the cart, pokes each type into
`sc9 + 1`, and lets line 40 redraw it.

**The world also decides who owns what.** 2520 makes every airfield on screens 0,
10, ..., 50 an enemy base (`bse(a) = 1`). Then 0 and 50 are made friendly
(`bse = -1`). In the shipped world, screens 10, 20 and 40 are enemy airfields. The
enemy fighters take off from them (870). Record 8's "capture all their airfields" (type 24)
means those.

### A mission: `MISSIONS.DAT`, 301-byte records

Lines 1663-1675: `field #1,289 as md$,12 as db$ : get #1,lvl+1`.

| bytes | field | meaning |
|---|---|---|
| 0-287 | `md$` | 8 briefing lines of 36 characters, space padded. 1670 centres every non-blank line |
| 288 | | a space (the field is 289 bytes) |
| 289-290 | `tgtx` (word, big-endian) | target screen. 0 = none: no target arrow (118) |
| 291-292 | `strtx` (word) | start screen. 0 = stay where you are. Otherwise `sx = strtx / 10 * 10` (1667) |
| 293 | `mission` | the mission **type**: an index into `mif(30)`, the success counter. The code decides what counts |
| 294 | `misf` | the counter starts at `misf - 1` (`dec misf`, 1675) |
| 295 | `mfin` | the mission is done when `mif(mission) >= mfin`, checked on landing at a friendly airfield (101 -> 530) |
| 296-297 | `bonus` (word) | x 1000 points when done (531) |
| 298 | `msb` | start bonus: 1-16 = `bm$(msb - 1)`, 0 = none (1673, 1699) |
| 299 | `meb` | end bonus, same numbering (1674, 531) |
| 300 | | a space |

`bm$` (DATA.DAT) numbered as `msb` / `meb`:

| no. | bonus | no. | bonus |
|---|---|---|---|
| 1 | 4 H.E. Bombs | 9 | 10000 Points |
| 2 | 8 A.G Rockets | 10 | 20000 Points |
| 3 | Bonus Fuel | 11 | 50000 Points |
| 4 | Extra Firepower | 12 | Bonus Aircraft |
| 5 | Extra Ammo | 13 | Repair Bonus |
| 6 | Engine Boost | 14 | Turbo Boost |
| 7 | Fire Extinguisher | 15 | Cluster Bomb |
| 8 | 5000 Points | 16 | Aircraft Repaired |

**Mission types are code.** Each one is a place in the listing that increments or
sets `mif(n)`:

| type | done when | lines |
|---|---|---|
| 2 | enemy fighters shot down (`mif(2)` +1 a kill) | 330 |
| 4 | the battleship is sunk (3 bomb hits) | 1092, 1108, 1682 |
| 5 | caught by the carrier's arrester net | 88 |
| 6 | the airfield at `tgtx` is destroyed (3 craters), or not ours at the briefing | 924, 1680 |
| 7 | the airfield at `tgtx` is ours at the briefing | 1681 |
| 9, 11 | vehicles destroyed. Type 11 also puts a convoy of 4 trucks on `tgtx` (1685), and the target arrow follows the lead truck for types 10, 11, 25-28 | 488, 470 |
| 15 | scene 6 (type 26, the gun post) cleared | 1072 |
| 17 | landed on `tgtx` | 530 |
| 20 | flown under the bridge (a type 8 screen) | 97 |
| 24 | no enemy airfield left | 875 |
| any other type > 2, except 11, 16, 19 and 20 | the flak buildings on `tgtx` destroyed. Only a scene screen (type 20-35) counts | 1073 |
| 8 | **the end**: the newspaper, +5,000,000, back to the title | 1690 |

The shipped types are 2, 14, 11, 20, 29, 4, 13, 24 and 8. Types 14, 29 and 13 use the
generic rule. DATA.DAT's unused `sct`/`mit` table pairs scenery with mission types
(24->14, 32->29, 34->13, ...). It shows which scenery each generic mission targets.
The code never reads it.

**Records 10-12 are never played.** The chain is record 1, 2, ... (`lvl + 1`, 531).
Record 9 is mission type 8, the ending, which goes back to the title (1690). Records
10-12 are copies of records 2-4 left in the file. The port calls the missions "1-11"
only as mission **types** (`mif`). There are 9 playable missions.

### What is random, and what is code

- **The world fill (2530):** at every new game, each type-0 screen from 2 to 50
  becomes `gt(rnd(12))` when `rnd(100) > 30`. `gt` = 0, 20, 21, 23, 25, 25, 30, 31,
  33, 20, 21, 23, 25 (DATA.DAT; 0 stays grass).
  - So a type 0 screen is "grass, or a random scene", and each game's world differs.
  - Types 4-7 are grass that is never replaced.
  - Screen 2 is always forced to the bridge (2525).
  - The decoration drawn on a type-0 screen (1401) is **not** random: it comes from
    `sx`.
- **At run time:** the enemy fighters (they spawn at the nearest enemy airfield,
  870), flak (165), the damage table (600), bonus drops from kills (330), and
  craters.
- **Code, not data:**
  - what each mission type means;
  - the truck convoy (1685, 2611);
  - the per-scenery tables in DATA.DAT: `gt` (the random pool), `scrb` (points per
    building), `fl` (buildings left before the flak stops).
  - DATA.DAT's `tr*` (6 x 13) and `sct/mit` tables are read and never used.
  - These are game tables, not level data, and `levels.py` leaves DATA.DAT alone.

### What the lead's reading got wrong

- **SKYSCRNS.MBK is not the screen art.** It is bank 8, the block table. The art is
  SKYPIC1/2.
- **There are no placed objects in the data.**
  - `so9 + sx*4 + slot` is bank 7, which is **zeroed** at every new game (2500). The
    game writes it at run time: a destroyed vehicle leaves its wreck `vb` and debris
    77/78 there (480-485). 490 draws them and flips 77 <-> 78 (`207 - id`).
  - `sno9` (per-screen object count), `ghx9` (crater bits) and `lc9` (buildings
    destroyed) are run-time state too.
  - `ghx9 = so9 + 105` overlaps the slots from screen 26 on. That is an original
    bug, which the port keeps.
  - The vehicles, ships and bridges come from the screen **type**. So does the flak,
    through `fl`.
  - The trucks and the `tr*`/`sct/mit` tables are code or unused data.
  - The only placed things in a level are the mission's **target** and **start**
    screens, so those are the map's objects.
- **The world is not per mission.** It is one strip per game, partly random.
- **Record 12 is not a mission.** It is dead data after the ending, as are records 10
  and 11.

## 2. The maps

`levels/missionNN.json`, one per record. It is plain Tiled 1.x JSON, embedded
tilesets, nothing else:

- **tile layer `world`**: 51 x 1 tiles of 320 x 176, the play area of a screen. The
  tile id is the screen type; the gid is type + 1. **Every map carries the same
  world.** The importer refuses maps that disagree.
  `levels.py sync-world <map you edited>` copies one map's world into all the others.
- **object layer `mission`**: the markers, as tile objects:
  - `target` (the HUD's TGT sprite, gid 38) on screen `tgtx`;
  - `start` (the Spitfire, gid 37) on screen `strtx`.
  - A marker's screen is the screen under its centre. There is no marker for 0.
- **map properties**:
  - `record` (int, the position in MISSIONS.DAT, 1..N);
  - `mission`, `misf`, `mfin`, `bonus`, `msb`, `meb` (int, as in the table above);
  - `briefing` (string, up to 8 lines separated by newlines).
- **tilesets**:
  - `skystrike_screens` (`skystrike_screens.png`, 36 tiles, 6 columns; tiles 18 and
    19 are crossed out);
  - `skystrike_markers` (`skystrike_markers.png`).
  - Every tile has an `is` property naming it.

## 3. Editing

**WebTiled (https://tiled.z0.lv/) is a viewer, not an editor.** This was tested in
headless Chrome against its code (github.com/justgook/web-tiled 1.6.0,
elm-tiled 3.0.2):

- To open a map, drag **three files** onto the page together: `missionNN.json` and
  the two PNGs. File > Open... with the same three files also works.
  - The tileset PNGs are matched **by file name**, so they must be dropped with the
    map.
  - It renders the world and the markers, and lists the layers and properties.
- It **cannot change anything**:
  - The tool buttons have no handlers.
  - Typing into a property field changes the text box, but not the map.
  - File > Save writes the **unchanged** map into the browser's IndexedDB as
    `hello.json`. There is no download.
- A map saved that way still imports byte for byte. WebTiled's rewrite is modelled in
  `levels_check.py`: properties sorted, `color: "none"`, `properties: []` on each
  layer, a wrong `nextlayerid`.
- The preview has no pan or zoom, so only screens 0-2 are on screen.

So edit with **desktop Tiled** (mapeditor.org) or a text editor, and use WebTiled to
look:

- **World:** select the `world` layer and stamp tiles from `skystrike_screens`. Then
  run `levels.py sync-world levels/missionNN.json`.
- **Target / start:** move the marker along the strip. To add one, insert a tile
  object from `skystrike_markers` and set its Class (Type) to `target` or `start`. To
  remove one, delete it.
- **Record fields:** Map > Map Properties. The briefing is a multi-line string.
- **A new mission:** copy a map, give it the next `record`, and place it in the chain.
  The set must still contain a type-8 record, and records after the first one are
  never played.
- Tiled 1.9+ saves `"class"` instead of `"type"` and a string `"version"`. The
  importer takes both. WebTiled cannot open those files, because its decoder needs a
  numeric version and `type`. Re-export them to view them there.

The maps keep to what WebTiled's decoder accepts; any of these makes it fail the
whole map:

- a string `version`;
- objects without `type` or `rotation`;
- properties not in the `[{name, type, value}]` form;
- an external tileset;
- an image path with a directory.

WebTiled draws only tile objects, so the markers are tile objects.

## 4. Commands

```sh
python3 tools/skystrike/levels.py export [--data DIR] [--out DIR]   # DAT files -> maps (default: the cart's -> levels/)
python3 tools/skystrike/levels.py import MAPS... --out DIR          # maps -> MISSIONS.DAT + SCRNDATA.DAT
python3 tools/skystrike/levels.py import MAPS... --cart             # ...into the cart's built-in data (then rebuild)
python3 tools/skystrike/levels.py sync-world MAP [DIR]              # one map's world -> every map of DIR
python3 tools/skystrike/levels.py disk MAPS... --out my.zmd         # maps -> a playable SKYSTRIKE disk
python3 tools/skystrike/levels.py check                             # the gate (below)
node tools/skystrike/render_tileset.mjs                             # redraw the two PNGs from the built cart
```

`MAPS` is map files or directories of them.

## 5. The validation rules

`import` and `disk` check every map and fail with the map, layer and position. They
never clamp or guess.

- **Map:**
  - tiles are 320 x 176;
  - it has exactly one `world` tile layer (51 x 1) and one `mission` object layer;
  - the `skystrike_screens` tileset is present.
- **Properties:**
  - exactly `record`, `mission`, `misf`, `mfin`, `bonus`, `msb`, `meb` and
    `briefing`: none missing, none unknown;
  - integers. `5`, `5.0` and `"5"` are accepted; anything else is refused.
- **Ranges:**

  | field | range |
  |---|---|
  | `mission` | 0-30 (`mif(30)`) |
  | `misf`, `mfin` | 0-255 |
  | `bonus` | 0-65535 |
  | `msb`, `meb` | 0-16 |
  | `tgtx`, `strtx` | screens 0-50 |

- **Briefing:**
  - at most 8 lines of at most 36 characters, printable ASCII only;
  - trailing spaces are ignored, since the file pads with spaces;
  - CRLF counts as a line break.
- **World:**
  - every screen has a tile: no empty cells, no flipped or rotated tiles;
  - every type is one the game draws (0-17, 20-35);
  - an airfield (1) only sits on a screen divisible by 10, because the bases are
    `bse(sx / 10)`;
  - screen 0 is the airfield (2352 pokes it back to 1 at every briefing);
  - screen 2 is 0 or 8 (2525 makes it the bridge anyway).
- **Markers:**
  - only `start` and `target` (by `type` or `class`), at most one of each;
  - each marker's tile is its own;
  - each sits on the strip, and not on screen 0 (0 means "none");
  - the start is on an airfield.
- **The set:**
  - records are 1..N with no gaps or duplicates, and 1-64 of them (the cart's
    buffer);
  - every map has the same world;
  - at least one record is mission type 8, or the briefing chain would run off the
    file. Records after it are allowed, with a note that they are never played.

## 6. Playing custom missions

The game BLOADs and GETs its level files from its disk, and so does the cart
(`scenes/skystrike/levels.zig`). At power-on it looks for `MISSIONS.DAT` and
`SCRNDATA.DAT` on the mounted `.zmd`. A file it finds replaces the built-in copy.
Either file may be left out.

- A file of the wrong size stops the cart on the error trap (2700) with the reason,
  and the cart stays there rather than quietly playing the built-in set.
  - `MISSIONS.DAT` must be 1-64 records of 301 bytes.
  - `SCRNDATA.DAT` must be 51 bytes.

To build and play a disk:

```sh
python3 tools/skystrike/levels.py disk my_levels/ --out my_skystrike.zmd
```

The command:

- packs `docs/demo-skystrike.wasm`, ZX0-packed when `zig-out/bin/zx0pack` exists;
- adds the two files, via `tools/mkdisk.py --file`.

Drop `my_skystrike.zmd` on the ZigMachine page (the upload box, `docs/upload-cart.js`)
or open `index.html?disk=my_skystrike.zmd` from `docs/`.

To change the **built-in** campaign instead, run `levels.py import levels/ --cart`
and rebuild. The gate then checks that the committed maps and the cart's files agree.

## 7. The gate

`build.sh` runs `apps/skystrike_levels.mjs` (tag `skystrike`). It checks:

- **The round trip** (`levels.py check`):
  - `import(export(original))` equals `MISSIONS.DAT` (3612 B) and `SCRNDATA.DAT`
    (51 B) byte for byte;
  - the committed maps import to exactly the cart's built-in files;
  - 22 broken maps are refused, each with its location;
  - maps rewritten the way old Tiled and WebTiled rewrite them still import
    unchanged.
- **A custom disk:** mission 1 is edited as a map (target moved to screen 30, a new
  briefing, screen 4 made sea in every map), and `levels.py disk` makes a disk of
  it. The cart, fed that disk through `diskReadBlock`, briefs and plays that mission:
  `tgtx` 30, and `sc9 + 4` is sea.
- **A bad disk:** a 300-byte `MISSIONS.DAT` stops on the error trap and stays there.
- **`--break disk`:** a disk of the built-in data must fail the custom-disk check.

The existing `apps/skystrike_headless.mjs` still runs the cart on the built-in data.
Because the gate proves that data equals the maps' import, it is data built from the
maps.
