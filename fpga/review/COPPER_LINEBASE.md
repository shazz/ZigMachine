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
`vdrow.h fetch()` would compare FB_BASE's rows, not the ones shown: such a plane is planned
**uncompared**, every covered line new every frame (as a PALREF-first plane: `vdl_palref_first`
becomes "uncompared first", plus `vdl_measure` names LBASE). Then no line of it is ever skipped, which
also keeps the board's copper in step (below). Overscan planes are UNKNOWN to the planner anyway, so
Mind Rewind is not planned at all. A `VD_BREAK_LBASE` mutant in test_vdirty.py.

**Open question found on the way (1.9.0, not LBASE's):** a SKIPPED line issues no PLANE pass
(`vseq.c layer()`, `vseq_group.c plane_line()`), so the copper does not apply that line's record;
the next issued pass then sees a record for a line already passed (`c_hy < line`) and STOPS the
list, where the browser applied every record. A plane with an unchanged list (no handler) can have
lines skipped, so a later changed line would paint with the wrong palette. To be checked with a
replay test before trusting the plan with lists; LBASE avoids it by being uncompared.

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

`libs/zig/effects/linelist.zig`: a per-line table `{base, hscroll, colour0}` (plus `.flicker` for
open borders) built into the plane's list each frame, only changed words stored (as
tcb_colorshock's `put`), no handler (FLICK replaces flickerBorder, so the plane groups on the board).
Encoders for hand-built lists: `copper.lbase(v)`, `copper.reg(hscroll)`, `copper.head(y, n)`.

## Proofs (each mechanism with its break)

- `machine/copper_test.zig`: valid LBASE, out of VRAM, `[27:21]` set, persistence over lines, frame
  reset, last-wins; overscan HSCROLL tests in video tests.
- A test cart (`linebase_test`: flip, sine wobble with LBASE + REG HSCROLL, a colour-0 raster, open
  borders) with a scene_hash harness named in build.sh.
- vsynth scenario (`vsynth_lbase.c`) in test_rtl_video.py, replayed on the RTL against the machine:
  LBASE in every mode, an overscan plane with REG HSCROLL, an LBASE out of VRAM (stop). Mutants
  (ZM_RTL_BREAK=1): LBASE ignored, applied a line late, not persisting, OVS HSCROLL ignored.
- One hp_sim slot (<= 6 frames) on the test cart: the board firmware's picture equals the browser's.
- Bitstream only after asking (Vivado lock, `--vivado-directives closure`).
