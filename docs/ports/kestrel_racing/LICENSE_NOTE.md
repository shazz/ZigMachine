# Kestrel Racing: licence and credits (R82, M0)

Kestrel Racing is an original flat-shaded racer. Its engine design is freds72's.

## The engine: freds72, MIT

- The 3D and physics engine is the Lua of freds72's PICO-8 racer (github.com/freds72/virtua-on,
  `carts/vracing_main.p8`, one commit dated 2021-05-25). His itch.io page states "Code license: MIT".
- **The repository has no LICENSE file.** Matt has asked freds72 to confirm MIT for the engine and the exporters
  (open question Q1 of `prototypes/racer_re/PORT_PLAN.md`). Until he does, the statement on the itch.io page is
  the only evidence. Save the page (URL, date, screenshot) next to the plan when it is next visited.
- Every Zig file ported from his Lua keeps "Copyright (c) freds72, MIT" and the MIT licence text in its header.
  M0 ports nothing: the reference harness reads his functions from a local clone at run time and copies none.
  M1 (the renderer spike) re-implements the pipeline's ALGORITHMS from `PORT_PLAN.md` section 1 (tile visibility by a
  ray DDA, the per-tile face collection with the back-face test, the vertex cache, the near-plane clip, the sort, the
  inner-face order); freds72's Lua text was not read for it. The files that follow his engine carry the notice:
  `apps/zig/scenes/racer/{frame,pvs,clip,xform}.zig`, `tools/racer/pvs_bake.py`.
- The title screen credits him ("engine based on work by freds72, MIT"), as the plan suggests.

## What is not used

- **No Sega data, no ROM data.** The `.p8` `__gfx__/__map__/__sfx__/__music__` sections, the data carts
  `vracing_0..12.p8`, every `models/*.blend` and the ROM rippers are not used: not copied, not read by any tool
  here, not used as a test fixture. The harness extracts only function text (the physics), never a data block.
- No Sega name, track shape, car silhouette, HUD layout, font or palette. The name is "Kestrel Racing" (Matt, 22 Nov).

## Our content: original, ours

The tracks, cars, palette, HUD and FM music are made for this game. Everything in `tools/racer/` is ours:
the track generators (`gen_track.py`: a procedural oval; `gen_city.py`: a stress city of boxes), the
`.ktrk.json` format, its validator, the Lua export and the harness glue.

## The Lua reference harness (M0)

`tools/racer/ref_harness.py` runs freds72's physics under **z8lua** (Sam Hocevar, the `pico8` branch, commit
`8575dfbc`): PICO-8's 16.16 numbers, its `sin`/`cos`/`atan2`/`sqrt`. z8lua is **local-only**: it is built under the
git-ignored `prototypes/racer_re/z8lua/` and is not in the repository.

- Its sources carry two licences: the Lua 5.2 files are MIT (PUC-Rio), and `fix32.h`, `lpico8lib.c` and
  `trigtables.h` (zepto8) say WTFPL v2 in their headers. The repo has no LICENSE file either, so this is read
  from the file headers.
- `trigtables.h` says its tables were "generated using PICO-8 code" (the exact `sin` and `atan2` values).
  That is a question for M2, when the Zig port needs the same trig: either generate our own tables (the physics
  would then match within a tolerance, not bit for bit), or accept the tables on the WTFPL header. It does not
  block M0.
- Local patch to the build: upstream's `sintable` lacks its last entry (index 0x1000, `sin(0.25)`), so
  `cos(0)` read past the array and returned 1.0966. The local copy appends `0x0000`.
