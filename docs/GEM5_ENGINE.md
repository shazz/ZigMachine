# GEM 5.0 step 1: the engine and the TOS 4 look

Status: **built on `feat/gem5-engine`** (9 Nov 2026), on top of the desk mode (`feat/gem-desk-ziggem`).
Plan: [GEM5_PLAN.md](GEM5_PLAN.md) phase 2 (look) and prototypes/kos1_plan/KOS1_ASSET_PACKS.md phases A-C;
decision: decisions.md 2026-11-09 "GEM 5 step 1". Matt: "look and speed first, features next".

## What it is

- **A new ROM module, `rom/gem/engine/`**, pure Zig with native tests (`engine_test.zig` in build.sh):
  - `obj.zig`: the AES object tree. OBJECT with ob_next / ob_head / ob_tail in one array, the types
    G_BOX .. G_CICON, the flags and states including TOS 4's FL3DIND / FL3DBAK / FL3DACT, TEDINFO, ICONBLK,
    a colour icon block, BITBLK. Two of ours: `CLIPKIDS` (children clipped to the box: a window's work
    area) and `G_DOTS` (GEM's dotted gesture outline). Every walk is bounded by the tree's length.
  - `find.zig`: objc_find (deepest, last sibling on top, HIDETREE skipped) and fm_button (radio groups,
    toggles, DISABLED, EXIT / TOUCHEXIT).
  - `draw.zig`, `paint.zig`, `paint_icon.zig`: objc_draw, clipped to one rectangle. The flat look is
    TOS 1's (SELECTED inverts); the 3D look is TOS 4's (grey face, light/dark edges, an activator
    pushes in, an indicator changes colour, both drawn 2 px larger). `extent()` is everything an object
    can paint (outlines, shadows, the 3D outset, a long string), so the damage pass can trust it.
  - `canvas.zig`: the 8 bpp raster with a clip; fills of 4,096 px and more go to the plane's CHISEL fill
    (blit.Dst), smaller ones are word stores (a blit costs ~800 cycles of fixed cost). No copies.
  - `scene.zig`, `damage.zig`, `compose.zig`: the screen as layers (one tree each, the rectangles it
    covers), a snapshot per BUFFER (the desk is double-buffered: the buffer drawn next holds the frame
    before last), the damage between them, and the compositor that paints each layer only in the
    damage minus what the layers above cover (the AES's rectangle-list walk).
- **The desk on it, `rom/gem/desktop/eng/`.** A frame runs ZigGEM's own step unchanged with the Gui
  muted (`gui/clip.zig`), so input, menus, windows and dialogs behave exactly as on the old path. Then it
  builds the layers from the desktop's state: the desktop and its icons, each window (chrome + its
  directory in a CLIPKIDS work area), the gesture outlines, the menu bar, the open drop-down, the dialog,
  the arrow. Everything sits where the old code hit-tests it.
- **Dialogs** stay on the old code this step: during the step they paint into their own box (the box
  they had last frame), and the compositor treats that box as an "external" layer it never paints.
- **The switch.** `deskSetEngine(v)` (system table 1.16): 0 the old path (the default), 1 the engine
  with the flat TOS 1 look, 2 with the TOS 4 3D look; bits 8.. are the harness's mutants.
  `-Dgem_engine=true` makes the engine the boot default (3D when a local asset set is built in).
  Low and medium never use it.
- **The icons are one set in every mode** (Matt, 9 Nov: "in low resolution, the same icons should be
  used as in desk mode"). `rom/gem/iconset.zig` picks each desktop icon once: the asset set's colour
  icon, else its mono icon, else the TOS 1.0 bitmap in `gem_icons.zig`. The engine (desk) and the old
  path (low, medium: icon.zig, dirview.zig) both draw from it, so with Matt's set low shows the TOS 4
  icons too. As real TOS 4 does, an icon is drawn 1:1 in every mode, never scaled: in low the 32 px wide
  icon looks twice as wide (the ST low pixel is 2:1), and in medium half as tall. A colour icon shows its
  colour image where the screen has the planes for it (TOS 4 takes the 4-plane image on ST low's 4
  planes; ST medium has 2, so the mono icon there), and a selected colour icon is the mono one inverted.
  The old path installs the VDI pens at palette 48..63 only when the set has a colour icon. The icon
  cell follows the set's tallest art (`icon.zig` BASELINE: 30 for TOS 1.0, unchanged; 32 for TOS 4, so
  the cell is 72x42 there, in every mode). Proof: `tools/gem_iconset_test.py` (a made-up set, 2 breaks).

## The assets: `-Dgem_assets=<dir>` (local only)

- Unset (the gate, the page, Pages): `rom/gem/engine/assets_none.zig`, an empty set: the engine draws
  with the TOS 1.0 set in the repo (gem_icons.zig, ZigOS's 8x8 and 6x6 fonts, deskarrow.zig's ARROW).
- Set: build.zig runs `tools/gem_assets_conv.py <dir> [--trees <zig_extract dir>]` (uv + Pillow) into
  the build cache. It reads Matt's reconstruction's manifest.json and PNGs: the TOS 4 desktop icons
  (FLOPPY, HARD, TRASH, FOLDER, PROGRAM, DOCUMENT), MultiTOS colour icons (the disk one replaces the
  floppy), the TOS 4 mouse arrow with its hot spot, the 6x6 / 8x8 / 8x16 fonts, the dither patterns,
  the 16-colour palette (the VDI pens, palette slots 48..63 while the engine runs), and with `--trees`
  the 104 TOS 4 object trees. A missing piece falls back to the built-in one.
- **Never commit** anything it produces, or a docs/ file built with it: build such a ROM into a scratch
  prefix (`zig build ... -Dgem_assets=... -p <scratch>`). The converter is proven on a made-up directory
  only (`tools/gem_assets_conv_test.py`, 3 break tests).

## Speed (apps/frame_cost.mjs, the board's cost model)

The desk, A:\ open, the pointer moving every frame (apps/gem_engine_cost.mjs):

| | est. Mc / frame | fps (model) |
|---|---|---|
| old path, before this branch | 2.72 | ~37 |
| old path now (icon.zig's artBox remembered: it re-scanned each 32x30 bitmap several times a frame) | 2.21 | ~45 |
| engine | 1.07 | 60 (0.70 of it is FRESCO's fixed plane cost) |
| engine, 3D, with Matt's TOS 4 set (scratch ROM) | 1.04 | 60 |

These are ESTIMATES from the cost model, not measurements: Matt read ~25 fps on the board for the old
path (9 Nov), where the model says ~37, so the model is optimistic for GEM by about 1.5x. The engine's
1.07 Mc leaves room for that; 60 fps on the board is plausible, not proven: only the board's OSD says.

A pointer move paints two 16x16 boxes; the engine's own work is ~0.15 Mc plus ~0.17 of I$ misses (the
frame's code is ~29 KB against a 16 KB I$). Only the board says what the real fps is.

## Proofs

- `apps/gem_engine_check.mjs` (gate `gem`): the engine paints the desk; frames with no input paint
  nothing (FB_BASE stays, a poisoned back buffer keeps every byte); a pointer move paints <= 512 px
  (two arrows) and nothing of a poisoned buffer outside them; a window dragged by its title bar paints
  its old and new places only and lands where dropped; after every gesture, painting the damage equals
  a whole repaint byte for byte; frame_cost old vs engine. `--break`: whole, noclip, onesnap, drop,
  engineoff are each caught.
- Native: rect lists (overflow, subtraction), malformed trees, find/button edge cases, clip and extent
  containment, 300 random edits where painting the damage equals a whole repaint.

## Return fires the default button

Matt on the board (9 Nov): Return did not close a dialog although its default button is drawn bold.
As TOS's form_do does, Return / Enter (codes 13 / 10) now fire the DEFAULT button of the open dialog
(`Gui.enter`, `buttonThick` border 3 / `buttonEx` default), on the old path and the engine alike; Show
Info's name field keeps its own Return. gem_engine_check closes Desktop Info with Return on both paths
(mutant `noenter`). What key code the board's glass sends for Return was not checked here.

## The look, checked by eye

Screenshots of the desk (old path, flat engine, TOS 4 engine with Matt's set: the desk, a drop-down,
Desktop Info, a window drag) were taken with a scratch ROM built with `-Dgem_assets` and compared with
gem_assets/aes340_tos4/components/*/windows/*.png. They stay local (prototypes/gem5_card/shots/). The TOS 4
window now follows the reference: white gadget faces with a grey shadow edge, the font's gadget glyphs,
TOS's grey mover, no drop shadow. Still different: the reference's gadgets are wider (its font is
8x16 at 640x400), and its menus and dialogs are TOS 4's own trees.

## Not in this step (honest list)

- The layout metrics stay TOS 1's (8x8 cells, 12x11 gadgets, an 11-row menu bar): the 8x16 font is
  converted and loaded, not yet the desk's system font. That needs the menu / window metrics read from
  `Screen.metrics()` in gui/menu.zig and gui/window.zig (low and medium must stay 8x8).
- Dialogs (alerts, Show Info, Set Preferences, Desktop Info) keep the old flat look and the old code.
- The TOS 4 trees are compiled in with `--trees` but nothing draws them yet: the desk's own menus,
  windows and icons are built from ZigGEM's state.
- The engine is not the default: it does not have every old feature's look (the icon drag ghost is two
  dotted boxes, not TOS's one "hat" outline; separators are dashes).
