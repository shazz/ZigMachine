# Copper LBASE + HSCROLL on overscan planes (HW 1.10.0): design (2026-10-31)

Matt's choice (option 1b of `prototypes/mindwind_re/ANALYSIS.md` §7, branch analysis/mindwind): a
per-line SOURCE ADDRESS in the copper list, and HSCROLL honoured on overscan planes, so an STE
line-list screen (Reservoir Gods' Mind Rewind: every line rewrites the video counter
`$FF8205/07/09`, HSCROLL `$FF8264` and colour 0) ports as data the machine applies, with no CPU
copy. It serves any later distorter / wobble / flip / line-zoom screen the same way.

## What the demo needs (ANALYSIS.md §2-4)

280 records a frame, each `{video address, HSCROLL, colour 0}`, written in the border between
lines; all four borders open (overscan, 280 lines x 416 px, KESTREL shows 400: crop 8 px a side);
no mid-line writes. In copper words a line is `HEAD, FLICK, LBASE, REG HSCROLL, PAL 0 x1, colour`:
6 words, 1,681 words (6.6 KB) a frame. Lines whose address/HSCROLL/colour do not change from the
line before need only the words that change (LBASE persists, see below).

## ABI

**HW 1.10.0** (`ZM_HW_VERSION = 0x0001_0A00`). No new register, no new export: no sys-ABI bump.
A new copper op, and a widened rule for an existing register:

| word | bits | meaning |
|---|---|---|
| LBASE | `[31:28]=5`, `[27:21]=0`, `[20:0]` v | from THIS line on, the plane's line source is v: the region byte offset of the line's first byte (logical column 0 of the plane's row, the left border in overscan, before HSCROLL) |

- **Persistence (the STE video counter):** a line r of the plane, after an LBASE v on line r0,
  reads `v + (r - r0) * stride` (+ HSCROLL where the mode adds it), until the next LBASE. Without
  any LBASE a line reads `FB_BASE + r * stride` as today. `r` is the plane's row (`py` for the
  physical modes, `py - 40` for the 320x200 ones); records come in increasing line order, so
  `r - r0 >= 0`.
- **Every frame starts from FB_BASE**, latched at the plane's frame start as today. LBASE never
  writes `REG_FB_BASE`: a handler or `frame()` reading FB_BASE never sees it, nothing is written
  back, and next frame is unaffected. STE mapping: FB_BASE = the base `$FF8201/03` (reloaded each
  VBL), LBASE = a write of the counter `$FF8205/07/09`.
- **All modes.** normal, scroll, fullscreen (its `% stride` column wrap then runs from v), overscan,
  medium (320 or 640/800 bytes from v). It is one address term shared by every mode on the board,
  so restricting it would cost a mux, not save one.
- **Validity:** `[27:21] = 0` and `OFF_VRAM <= v < OFF_VRAM + VRAM_BYTES` (`0x1100 .. 0x1010FF`),
  as PALREF's offset is checked. Otherwise the list STOPS there (the existing rule: what the record
  applied before the word stands). Several LBASEs in one record: the last wins.
- **Alignment: none.** `zm_video_fetch.v` is byte-granular (beats from `addr & ~7`, the painter from
  `addr & ~3`), as SCROLL's HSCROLL already uses; chunky is one byte a pixel, so v positions a line
  to the pixel.
- **Bounds past v** are the cart's, exactly as for FB_BASE today: the line's bytes and the following
  lines' must stay in VRAM; bytes past VRAM's end are unspecified (the browser reads the region's
  PFB, the board whatever DDR holds there).

**HSCROLL on OVERSCAN planes** (`FB_MODE_OVERSCAN`): the SCROLL-mode rule verbatim. HSCROLL is a byte
(= logical pixel) offset added to the line's first byte, any u16, NO wrap (it reads on into the next
row, as the STE reads one more 16-px chunk), re-read every line AFTER the plane's HBL handler and its
copper record (so `REG HSCROLL` in the list, or a handler, moves that very line). The FULLSCREEN
mode keeps its own rule (latched once a frame, columns wrapped `% stride`). Medium overscan is not
changed. With byte addressing HSCROLL is redundant with LBASE (v + h); it is there so an STE record
ports word for word, and so a wobble that keeps the address costs one REG word a line.

Existing carts: every writer of HSCROLL is a SCROLL plane (scroll_demo) or writes 0
(`resetForScene`, the C/Rust tvnoise headers); the gate's scene_hash over every cart proves no
picture moves.

**Old machine:** op 5 is reserved on 1.9.0, so a 1.10 list stops at its first LBASE there (the same
policy as a 1.9 cart on 1.8: hosts hand carts no hwVersion, a 1.10 cart needs a 1.10 system).

## Machine (browser reference)

- `machine/copper.zig`: `OP_LBASE = 5`, `Effects.lbase: ?u32`, the check above; header comment is
  the spec the RTL mirrors.
- `machine/video.zig`: per plane-frame state `{lb = FB_BASE, lrow = 0}`; `lineStart` (after the
  handler and the record) sets it on an LBASE; every `renderPlane*` takes each line's source from
  `lb + (row - lrow) * stride` instead of a buffer pointer taken once a pass; overscan adds HSCROLL
  read after `lineStart`. The line-address helper goes in its own file (video.zig is 467 lines).

## RTL (board)

- `zm_video_copper.v` DEC: op 5 with `[27:21] = 0` and v in VRAM: a one-clock `lb_we` with v and
  `row0 = phys ? line : line - 40` (it already decodes `phys`/`covers`); else stop.
- `zm_video_latch.v`: per plane `r_base[p] <= v`, `r_lrow[p] <= row0` on `lb_we` (LATCH reloads
  FB_BASE and zeroes `r_lrow`). The latch, not `regs`: FB_BASE in the register copy stays the cart's.
- `zm_video_plane.v`: `prod_3 <= (row_2 - lrow_2) * stride_2` (try the DSP48 pre-adder first, else
  the subtract in stage 1), and `sc_2 <= (m == SCROLL || m == OVS) ? hs_live_i : 0`. The `moved` /
  `held` rule already holds a pass until its inputs have settled four clocks; the copper phase ends
  before `pl_go`, so the latch write lands first.
- Estimate: +40-80 LUT (a 21-bit and a 9-bit LUTRAM write port, one 9-bit subtract, one mux term),
  0 BRAM, 0 DSP if the pre-adder takes it. OOC synth of zm_video_comp before any bitstream; the
  board build is at 89.1 %.

## Planner (fpga/cycles vdirty)

A list with an LBASE names source rows elsewhere in VRAM that may change while the list does not, and
`vdrow.h fetch()` would compare FB_BASE's rows, not the ones shown: such a list always counts as
changed (`vdl_measure` names LBASE), so every line its plane covers is new every frame, and a plane
whose list opens with one is planned **uncompared** (as a PALREF-first plane). Overscan planes are
UNKNOWN to the planner anyway, so Mind Rewind is not planned at all. A `VD_BREAK_LBASE` mutant in
test_vdirty.py, caught on linebase_test's phase B, whose lines between two LBASEs carry no record.

The skipped-record issue found while designing this (a skipped line issues no PLANE pass, so the
board's copper never applied its record and stopped the list at the next pass) is fixed on main by
bb92bfc6: a line holding a copper record is never skipped (`vdl_records`, VD_BREAK=RECORDS). That
alone would not cover LBASE: the lines BETWEEN two records read rows the LBASE moved, which is what
the always-changed rule covers.

## Why not "REG writes FB_BASE (and BACKGROUND, PLANE_ENABLE)"

Proposed by the retro-hardware survey (docs/RETRO_HW_FEATURES.md, study/retro-hw-features) as the
general form. Weighed and not taken for this op:

- **FB_BASE is a u32**; REG carries a u16 in one word. Writing it is two REGs or a two-word REG,
  a second decode path in the copper.
- **REG writes the register**, which the browser keeps in memory and the board writes back: a
  per-line FB_BASE would persist into the next frame (the list must restore it at line 0), and the
  value must be the VIRTUAL base `A - r * stride` (it can go below VRAM, so it cannot be checked).
  LBASE is the STE's counter: the line's own address, checked, gone at the frame's end, no
  write-back. The latch write it needs is the same either way; REG-FB_BASE adds the write-back.
- **BACKGROUND and PLANE_ENABLE are global**, and a plane's list applies before that plane's pass,
  AFTER the line's BG pass: a plane list cannot move them for its line. They need a GLOBAL list
  (one more REG_*_COPPER, applied before the BG pass, the global handler's slot), where
  `REG BACKGROUND` would remove swedish_newyear's 0.46 Mc of handler. Op space is left for it (6..14
  reserved); a separate design.

**Settled (survey point 1):** SCROLL mode's HSCROLL past the row end is the same on both machines:
video.zig reads `vy * stride + hs` (16-bit, no wrap), the RTL adds `hs_live` to the address
(`zm_video_plane.v` stage 2) and fetches byte-granular from there. Only FULLSCREEN wraps (`s0 = hs
% stride`, both machines). Not a mismatch; a handler can already re-point a SCROLL line forward by
up to 65,535 bytes, never backward: LBASE is the general form.

## ZigOS

`zg.linelist` (`libs/zig/effects/linelist.zig`): a table of `Line{ base, hscroll, colour }` (one per
raster line from `first_row`) built into the plane's list each frame by `build(list, lines, opts)`,
storing only words that changed (as tcb_colorshock's `put`). It writes an LBASE only where a line does
not follow on from the one above (`base != prev + stride`), REG HSCROLL and PAL colour 0 only on a
change (always on the first line: both persist across frames), and FLICK on every line with
`.flicker` (open borders with no handler, so the plane groups on the board). `zg.linelist.install(fb,
rows, flicker)` allocates and publishes the list (HBL position at the magic column for FLICK);
`fb.lineAddr(x, y)` is the region offset of a plane pixel. A Mind Rewind line maps to
`.{ .base = lineAddr(stripes_x + 8, row), .hscroll = h, .colour = c0 }`.

## Proofs (each mechanism with its break)

- `machine/copper_lbase_test.zig`: valid LBASE (odd byte, VRAM's last byte), out of VRAM and bits
  27..21 set stop the list with the record's earlier words standing, last wins, persistence.
  `libs/zig/effects/linelist_test.zig`: the words built, only changes, the size check.
- `apps/linebase_check.mjs` (machine only, build.sh): two planes against `apps/linebase_model.mjs`,
  pixel for pixel: overscan with LBASE, run-on, HSCROLL per line past the row's end, colour 0, open
  borders and the stop; normal with a flip and an ignored HSCROLL; frame 2 restarts from FB_BASE.
  `--break` drops each rule from the model in turn and must be caught; it fails on the 1.9.0 machine.
- Test cart `linebase_test` (cart 110, menu "LINE LIST TEST"): phase A overscan wobble / line zoom /
  flipped bands / colour-0 raster through open borders, phase B a scroll plane whose list shows, in
  8-line bands in reverse order, rows the CPU draws in (one LBASE a band, the lines between with no
  record). `apps/linebase_test_headless.mjs` (gate, 420 frames) checks the picture against
  the model of the list the cart built, with two `--break` mutants.
- Planner: `test_vdirty.py` runs the cart's phase B (LBASE on a comparable plane) with no
  mismatch, and `VD_BREAK_LBASE` (an LBASE list compared like a PAL one) must mismatch.
- vsynth scenario `lbase` (`tools/video_dump/vsynth_lbase.c`) in test_rtl_video.py, replayed on the
  RTL against the machine: LBASE in all of overscan / normal / fullscreen / medium, REG HSCROLL on
  overscan past the row's end, an LBASE outside VRAM (stop), frame 2 rebuilt. Mutants
  (ZM_RTL_BREAK=1, video_mutants.json): LBASE ignored, its row not kept, not persisting, its row
  one off, VRAM unchecked, row not reset at LATCH, overscan HSCROLL ignored.
- One hp_sim slot (<= 6 frames) on the test cart: the board firmware's picture equals the browser's.
- Bitstream only after asking (Vivado lock, `--vivado-directives closure`).
