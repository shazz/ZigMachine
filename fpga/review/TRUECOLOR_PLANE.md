# FRESCO true-colour plane mode: design and cost (study, 2026-11-01)

Matt's ask (31 Oct, confirmed 1 Nov): one plane in true colour, RGB565 first (Falcon-like: half the
bandwidth of 8888, two pixels a 32-bit store), 8888 as an option; the cart writes the final format, no
palette lookup, no compositing for that plane if possible, maybe scanout straight from the cart's buffer.
Driver: the Falcon port of "Are You Sitting Comfortably?" (`prototypes/falcon_ays_re/README.md`). Study
only: no RTL, machine or cart change on this branch. Cycles are sys (100 MHz) unless marked comp
(125 MHz, 0.8 sys); a 60 Hz frame is 1.67 Mc.

## The short answer

**Build the 565 plane as a compositor citizen through the painter (option A0): a new per-plane
`FB_MODE`, ~80-120 LUT, 0 BRAM, 0 DSP.** The painter reads a half-word instead of a byte and bypasses
the palette RAM with a 565 -> 8888 expansion that is pure wiring; the fetch, the fetch buffer, the mixer,
the row I/O, the dirty-line planner, the copper's HSCROLL/LBASE/FLICK and the browser's canvases are
untouched, and the PFB stays the oracle (scene_hash hashes it, board pictures equal the browser's). It
saves FRESCO nothing (one pass a line, as any plane); what it saves is the CART's work (no quantisation,
no mpp planes: mpp_truecolor's 4-plane mode becomes one plane, -0.6 to -1.8 Mc) and it gives the Falcon
port its native format for pictures, gradients, feedback blur and additive light.

**It does not fit for free.** The combined bitstream `integrate/combo-v2-fit` is at **15,724 LUT
(89.3 %), 4,400 of 4,400 slices (100 %), 70/80 DSP, 50/60 BRAM tiles**, and board_combo7 (the copper
LATCH a clock later, routed 1 Nov 17:24) **misses on both clocks: sys WNS -0.532 ns (259 endpoints),
comp -0.927 ns (333), sys->comp -0.201**, where board_combo5 had sys +0.087 / comp -0.468. Slices, not
LUT %, are the binding constraint, and the mode's logic lands in the comp domain, which is the clock
already failing. So the mode goes in only against a cut of at least its own size, and only after the
combined build closes. **The cleanest payer is inside FRESCO itself**: `zm_video_regs` (474 LUT) answers
the sequencer's read-back through a combinational 32:1 x 32-bit mux over 18 stored words, and the
firmware reads exactly six words (BACKGROUND, BEAM_COUNT, BEAM_DROPPED, FRAME, HSCROLL x2:
`vseq.c:101-105`, `vseq_group.c:63`); a 6-way read saves an estimated 60-120 LUT, net ~0 for the mode.
Behind it stand the roadmap's costed cuts (QUEUE ring read-through ~-150 + 1 RAMB18, TRIANGLE edge walk
~-100, pxq 16 slots ~-80-150, bus_timeout ~-30-50) and the read-bypass decision (+~120 if kept).

Scanout straight from the cart's buffer (option B) is the per-plane form of FRESCO_OPTIONS idea 1, which
the 2026-10-24 decision closed: ~150-300 LUT, it saves ~0.46 Mc only when the 565 plane is the whole
picture, the board's picture stops equalling the PFB, and the cart must double-buffer against the beam.
Not now; costed below in case the Falcon port measures FRESCO-bound, which a CPU blur over 76,800 pixels
makes unlikely.

## Where the numbers come from

- **The chip**: `ZigMachine-combo/fpga/build/board_combo7/gateware/platform_z7_{utilization_place,
  utilization_hierarchical_place,timing}.rpt` (post-route, the log ends in write_bitstream).
- **FRESCO's bill** (combo7 placed hierarchy, LUT): zm_video_out 2,449 = u_comp 2,274 (u_cop 536,
  u_regs 474, u_pp 474 = u_plane 230 + u_latch 147 (121 LUTRAM) + u_paint 80, u_bg 193, u_mix 168 + 6 DSP,
  u_pass 143, u_row 135, u_fbuf 86 + 8 RAMB18, u_wb 50) + scanfetch 55 + scan 25.
- **Pass phases** (FRESCO_OPTIONS.md A, comp clocks): LOAD 528, STORE 484, fill 403, fetch ~170-180,
  paint 329/408, mix 406, fixed ~171.
- **Bandwidth**: `fpga/review/reports/bandwidth_summary.json` (tutorial: scanout 53.8 MB/s, row I/O
  168 MB/s for one plane layer, DDR 10.8 % of 2,133 MB/s).
- LUT estimates below are counted from the RTL (muxes at one LUT6 per 2:1 bit, compares at ~0.4 LUT a
  bit) and marked **est.**; OOC-measured figures are marked **OOC** (section "Measurements").

## Options ranked by LUT

| # | design | LUT (est.) | BRAM/DSP | FRESCO saved | exact vs browser | gives up |
|---|---|---:|---|---|---|---|
| A0 | **565 through the painter**, new FB_MODE, compositor citizen | **80-120** | 0 / 0 | 0 (+40-50 fetch beats a line) | yes, PFB identical | nothing: planes over/under it, HSCROLL, LBASE, dirty lines all work |
| A0+8 | + 8888 as a second mode | +30-50 | 0 / 0 | 0 | yes | 2x VRAM and bandwidth; needs the painter's 9-bit word index |
| A0+K | + a 565 colour key (one value transparent) | +6-10 | 0 / 0 | 0 | yes | one 565 value |
| A1 | A0 + first-layer shortcut: expanded row straight into the accumulator, no PAINT/MIX | +~100 | 0 / 0 | ~650 comp a line = 0.15-0.18 Mc on 280 lines | yes | nothing (only when `cmd_first`) |
| B | **scanout from the cart's 565 buffer**, no compositing | 150-300 | 0 / 0 | all of it: ~0.46 Mc (one 400x280 layer) + ~170 MB/s row I/O | **no**: picture != PFB; tears unless the cart flips at VBL | planes over/under it, dirty lines, the oracle; reverses the 2026-10-24 decision |
| C | 16-bit pixel lanes in CHISEL (BLIT/FILL/AFFINE/MAP, 16-bit key) | 150-250 | 0 / 0 | n/a | n/a | not needed by the Falcon parts (below) |

Why A0 is small: every other stage already carries the right width. The fetch buffer is 256 beats x
64 bits = 2 KB; a 565 line is 640 B (80 beats) at 320 px and 800 B (100 beats) at 400 px, under the
fetcher's 1,021-byte / 256-word limit. The line buffer and the mixer already take `{A, B, G, R}` 32-bit
pixels: the palette's output format IS the mode's output. The row I/O moves 800-pixel rows whatever
the plane. 8888 is cheaper in logic still (the fetched word is the line-buffer word, no expansion),
but a 320-px 8888 line is 1,280 B = 320 words, over the fetcher's 256-WORD check and the painter's
8-bit word index (the buffer itself holds 160 beats): the check becomes beats and the index 9 bits.

## A0: the RTL change sketch (`fpga/rtl/video/`)

**`zm_video_plane.v`** (230 LUT): two more mode values, `TC` (5: 320x200 window, doubled at raster
x 80, lines 40..239) and `TCF` (6: 400x280, doubled from x 0, lines 0..279, borders always open: a
Videl mode, nothing to earn). `len = ncols << 1`; `ncols` as normal / fullscreen; `wrap` 0 (no
fullscreen modulo); the scroll term `sc_2 = hs_live` as SCROLL/OVS (live HSCROLL, a byte offset, no
wrap); a `tc` flag taken at `go` beside `single`/`wrap`. Est. +15-25 LUT: the mode compare widens by
two values, `len` and `ncols` get two mux cases, all on the `*_q` register stage (one clock, as today).

**`zm_video_paint.v`** (80 LUT), the three stages:

- stage 0: `bi = align + (tc ? {c, 1'b0} : c)` (11-bit 2:1 mux, est. 11 LUT); `fb_raddr = bi[9:2]`
  unchanged;
- stage 1: beside `byte1 = fb_rdata[sel1*8 +: 8]` -> `pal_raddr`, select the half-word
  `half1 = fb_rdata[sel1[1]*16 +: 16]` (16 x 2:1, est. 16 LUT) and REGISTER it into stage 2
  (16 FF: the palette read takes the clock the 565 path must wait too);
- stage 2: `lb_data <= tc2 ? {8'hFF, b8, g8, r8} : pal_rdata` with `r8 = {h[15:11], h[15:13]}`,
  `g8 = {h[10:5], h[10:9]}`, `b8 = {h[4:0], h[4:2]}` (wiring) -> 32 x 2:1, est. 32 LUT. The key
  option: `a = (h == key) ? 0 : 255` (16-bit compare, est. 6-10 LUT).

**`zm_video_planepath.v` / `zm_video_latch.v`**: the `tc` flag travels with `single`; nothing new is
latched (the mode byte is). **`zm_video_fetch.v`, `zm_video_mix.v`, `zm_video_rowio.v`,
`zm_video_pass.v`, `zm_video_copper.v`**: unchanged. The copper's PAL/PALREF records on a TC plane
write a palette the plane never reads (no effect, both machines); REG HSCROLL, LBASE and FLICK apply
(FLICK on mode 6 has nothing to open).

**Timing**: the two muxes sit on short paths (block RAM output -> one LUT -> flop) and add no carry
chain; the painter is not on either failing path of combo7 (the copper's LATCH decode, the audio
scheduler). Still: OOC at 8 ns before any bitstream, as the copper did (its OOC WNS +0.235 ns became
comp -0.468 in the dense placement).

**Firmware** (`fpga/cycles/vseq.c`, `vplan.h`, `vdirty.h`): the mode dispatch gives the plane's
handler its line numbering (logical for 5, physical for 6) and the planner the bytes a line fetches
(640 / 800) for its row compare; `vseq_group_ok` treats it as a normal/overscan plane. ~20 lines, no
new command. `apps/frame_cost.mjs`: a 565 plane costs a normal/overscan pass.

## The browser machine and the ABI (HW 1.12.0)

- **`FB_MODE` 5 `TRUECOLOR`** (320x200) and **6 `TRUECOLOR_FULL`** (400x280). A pixel is a
  little-endian `u16` `R5 G6 B5` = `(r << 11) | (g << 5) | b`; `FB_STRIDE` is in BYTES (640 / 800; the
  RTL's `row * stride` and video.zig's `lb.at` are bytes today, HW_API's "in px" is the 8-bit case);
  `HSCROLL` and LBASE are byte offsets as in every mode: a cart keeps them even (an odd one shows a
  byte-swapped line, as an odd video base would on an ST). Alpha is 255 everywhere the plane covers.
- **Expansion, one formula in both machines**: bit replication, `R8 = r << 3 | r >> 2`,
  `G8 = g << 2 | g >> 4`, `B8 = b << 3 | b >> 2`, so 0xFFFF is white and 0x0000 black. (Hatari's
  Videl conversion to check when the port's pictures are compared: open question 3.)
- **`REG_RESOLUTION = RES_TRUECOLOR (1)`** already exists: a legacy "border-open" value, `isTruecolor()`
  in video.zig has no caller, and ZigOS's `Resolution.truecolor` writes it to no effect. The new thing is
  per plane; the legacy value stays as it is (renaming the enum member is a ZigOS cleanup, not ABI).
- **`video.zig`**: `renderPlaneTruecolor(fb_id, full)` (~25 lines): per line `lineStart` (handler,
  copper), then `put2(out, py, x, expand(u16 at row + 2 lx))` over 320 or 400 columns. The PFB stays
  RGBA, so `sealed-loader.js` (one canvas a plane, `putImageData` of the PFB) and `scene_hash.mjs` change
  nothing. The native host (vmix/vsynth, `tools/video_dump/`) gets the same function for the RTL replay.
- **Falcon pictures are big-endian 565** (`png/ice_*.png` of the RE: header `0400 0140 00F0`, then BE
  words): the asset converter swaps bytes once at build time.
- **ZigOS**: `setTruecolorPlane(plane, .window | .full)` (vramAlloc 128,000 / 224,000 B; double-buffered
  448 KB of the 1 MiB pool for mode 6, 8888 double would be 896 KB), a `TcFB { pixels: []u16, w, h, stride }`,
  `zg.tc.rgb565(r, g, b)`, `fill`, `put2` (two pixels an aligned u32 store: a u16 store pair costs the
  same DDR time and a misaligned u32 traps, ~210 cycles), `copyRect` (CHISEL byte copy, W x 2 bytes).
- **Register block**: no new register (0x00..0x7F is full but for 0x02-03, 0x0C-0F, 0x12-1F, 0x5A-5B,
  0x66-67); the key, if built, is one u16 for all TC planes at 0x5A.

**Tests** (each with its break, `ZM_RTL_BREAK=1`): a native test of `expand` over all 65,536 values
against the formula; synthetic frames in `test_rtl_video.py`: a 320x205 gradient that covers every 565
value in one frame, a 400x280 mode-6 frame, HSCROLL even and odd, an LBASE record, a TC plane under and
over an 8-bit plane with alpha; mutants: expansion by shift only (no replication), the other half-word,
a 320-byte fetch of a 640-byte line, stride taken as pixels. A `s:truecolor` synthetic in the gate and
one shelf cart (mpp_truecolor gains a mode 4 "565": the gallery's converter already makes the pictures).

## CHISEL and 16-bit pixels

CHISEL is a LOGIC blitter: `D = LF(A, B, C)` per bit, a colour key, halftone, area fill. **Feedback
blur, additive light and motion blur are arithmetic (adds, averages, saturation) and cannot be CHISEL
ops at any pixel width**; they are CPU work in the port whatever the plane mode (or a future arithmetic
op, out of scope). What a 16-bit lane width would buy: FILL of one 565 colour (today a FILL writes one
byte value: only colours with equal bytes), a 16-bit colour key, AFFINE/MAP with a 565 texture (the
env-mapped shapes), MIRROR by pixel not byte. Cost basis: pxu 689 (q 616, 100 LUTRAM), rd 126, sx_/tex
607, chk 618, regs 991; a lane-width parameter touches px, pxq, tex, the strobes and the key compare:
**est. 150-250 LUT, unmeasured, in a block already over its LUT-neutral target by 952**.

**What works today on a 565 plane with the 8-bit CHISEL**: BLIT copies with no key and `MT_B` (a W-px
rect is a W x 2-byte rect; the clip is D_STRIDE = 640 bytes wide, so ZigOS doubles x and w); CLEAR to
black or white (0x00 / 0xFF bytes); AFFINE/MAP into an 8-BIT plane layered over or under the 565 one
(the compositor merges them: a second plane, +0.19-0.59 Mc). **Verdict: not needed for the Falcon
port; do not build.**

## What the Falcon intro's parts need (README's part list)

| part | technique | from the mode | CPU budget note |
|---|---|---:|---|
| 1 red blurred text, 6 chosneck glowing logo | feedback blur on a 565 buffer | mode 6, the cart reads frame N-1 / writes N (single buffer suffices: FRESCO reads after frame()) | 320x240 = 76,800 px; 1.67 Mc / 76,800 = **21.7 cycles a pixel at 60 fps**, 43 at 30: a 565 unpack-add-pack blur is ~20 ops a pixel plus D$ misses, so half-res or 30 fps |
| 2, 5 coloured blobs, flash, particles | additive light | 565 saturating adds by the CPU (ZM-X helps: packed adds) | same budget; particles alone fit an 8-bit plane over it |
| 3 ship logo on a blue radial gradient | gradient = 565 picture; logo 3D = ZM-X mulsh + CHISEL spans into an 8-bit plane over it | mode 6 picture + one 8-bit plane | the second plane: +0.19-0.59 Mc |
| 5 RG logo frames (5 x 320x240 565) | pictures | mode 6 at (40, 20), border filled once | 38,400 stores = 0.09 Mc a full repaint |
| 7 offset-map flames, dithered b/w | 8-bit texture through CHISEL MAP with a fire palette | **none**: an 8-bit plane does it | MAP is hardware |
| 8, 9 env-mapped shape and ball-oid | ZM-X tex2d into 565 (grey / orange env maps) | mode 6 | DSP work on the Falcon: the heaviest part |

So the mode carries parts 1, 2, 3 (gradient), 5, 6, 8, 9: a per-pixel 565 format with no quantisation
step, which is what the port's blur and light need (a palette plane would need a 256-colour
requantisation of every frame: more CPU than the effect). **The port's limit is ZIGGY's arithmetic,
not FRESCO**: one 565 plane costs FRESCO ~0.46 Mc a frame at 400x280 (280 passes, every line dirty
under a blur), 0.28 with A1; the blur itself is 1.5+ Mc at full resolution.

## DDR bandwidth

| stream | bytes a frame | MB/s at 60 Hz |
|---|---:|---:|
| 565 plane fetch, 320x200 / 400x280 | 128 / 224 KB | 7.7 / 13.4 (8-bit: 3.8 / 6.7) |
| 8888 plane fetch, 320x200 / 400x280 | 256 / 448 KB | 15.4 / 26.9 |
| the cart's own writes of the plane (full repaint) | 128 / 224 KB | 7.7 / 13.4 (32,000-56,000 posted stores: 0.07-0.13 Mc of cart time) |
| composite row I/O, one plane layer (tutorial) | 2.8 MB | 168 |
| scanout of the picture | 0.9 MB | 53.8 |
| DDR3-1066 x16 peak | | 2,133 (tutorial total 231 = 10.8 %) |

A 565 plane adds under 1 % of the DDR; the composite row's round trip stays the big stream (what
PLANE_INTERLEAVE.md found). Option B would remove that layer's row I/O and read 13.4 MB/s instead of the
picture's 53.8. 416 px wide is more than the raster's 400: not a geometry this machine has.

## Option B in detail (costed, not recommended)

`zm_video_scanfetch` (55 LUT) gains: a second base and a 640/800-byte row stride latched at the VBL
with `base` (per-line `addr += stride`, 32-bit add, est. 40 LUT), 80/100-beat requests, a serialiser
turning each 64-bit beat (4 px) into two 48-bit pair writes of doubled pixels (est. 60-80), the
expansion (wiring), a mode/base mux in `zm_video_out` (est. 50) and black (or BACKGROUND, 24 more
bits from u_comp) outside the plane's rows for mode 5 (est. 20-40); the firmware skips the plane's
passes and PRESENT still swaps. **Est. 150-300 LUT, all comp domain.** It applies only when the 565
plane is the whole picture (no plane over or under it, no BEAM, no global handler); the shown buffer is
the cart's live one, so the cart must draw into the buffer not shown and flip `FB_BASE` for the next
VBL, which the browser cannot enforce (a cart that draws into the shown buffer is right in the browser
and tears on the board); and `tools/board_pic.py`'s picture no longer equals the PFB for that plane.
Saving: the plane's 280 passes, ~2,070 comp = 1,660 sys a line = **0.46 Mc**, and ~170 MB/s. That is
Matt's "~0.7 Mc" (plane-major with the PFB store: 2,536 comp a line = 0.57 Mc, plus bookkeeping).
It reverses FRESCO_OPTIONS "Decision 2026-10-24" (stay frame-serial, keep the oracle) for one plane.

## Where the LUTs come from

1. **`zm_video_regs` read-back, 6 words** (`cpu_rdata = regs[cpu_rword*32 +: 32]`, a 32:1 x 32 mux
   over the 18 implemented words): the sequencer reads BACKGROUND, BEAM_COUNT, BEAM_DROPPED, FRAME
   (`vseq.c` copy_back) and the two HSCROLL words (`vseq_group.c` vseq_copper_end); no other reader
   (`cpu_rword` comes from `zm_video_cdc.py:152` only). A 6-case read answers 0 elsewhere. **Est. -60 to
   -120 LUT**, no behaviour change for the firmware; a break test reads a 7th word in the board-SoC sim.
2. The roadmap's costed cuts, in its order: QUEUE ring read-through (~-150 + 1 RAMB18, a read latency
   a descriptor), TRIANGLE edge walk (~-100, faster too), pxq 16 slots (LQ 5 -> 4, est. -80 to -150 of
   q's 616), bus_timeout None (~-30 to -50), the halftone sniff (~-20, ABI).
3. The read bypass (+~120, unmeasured): shipping the `nb` variant frees it.
4. Inside FRESCO, smaller: u_bg 193 (the BEAM span painter) and u_cop 536 are the next candidates, but
   both are measured, exact and new; leave them.

**Fit verdict**: A0 (~100) against cut 1 (~-90) is LUT-neutral and slice-light (muxes, 30 flops, no
carry); it still needs the combined build to close first (combo7 misses by 0.93 ns on comp and the
slices are at 100 %), then an OOC of `zm_video_comp` with the mode at 8 ns, then a bitstream the lead
builds. If the combined build needs more room anyway, cuts 2-3 are the pool, and the mode is a sixth of
the copper's size.

## Risks and open questions

1. **Timing in the dense placement**: OOC slack has not predicted the board's (copper +0.235 OOC ->
   -0.468 placed). The mode adds no carry chain, but every comp flop is one more in a 100 %-slice design.
2. **Slices at 100 %**: a LUT-neutral change can still fail to place if it adds control sets; keep the
   16 new flops on the painter's existing enable.
3. **The expansion formula** must equal what the port's reference pictures expect: Hatari's Videl
   565 -> 888 conversion to be read before the ABI is pinned (replication vs shift; a shift makes 0x1F
   248, not 255).
4. **HSCROLL / LBASE in bytes**: odd values are allowed and ugly (ST-like) or refused and counted (a
   compare, ~8 LUT): Matt's call; the doc assumes allowed.
5. **The colour key** (+6-10 LUT): without it a 565 picture cannot sit OVER an 8-bit plane with holes;
   with it one 565 value is lost. The Falcon parts put the 8-bit plane over the 565 one, so v1 can skip it.
6. **The cart's arithmetic**: 21.7 cycles a pixel at 320x240x60 Hz is the port's real wall; the mode
   removes quantisation, not the blur. Measure one blur part on the board before committing to 60 fps.
7. **8888**: cheaper in logic (+30-50), double the bandwidth and VRAM; the Falcon has no use for it.
   Build it only when a cart asks (the FPU twins' raytracers would).
8. **mpp_truecolor**: its 4-plane mode (1,020 colours a line through copper lists) is the mode's first
   shelf customer and A/B on the board: 4 planes -> 1 saves 0.6-1.8 Mc there.

## Measurements

OOC runs planned (one Vivado at a time, under `prototypes/_gate_logs/build.lock`; the script takes
`vivado.lock` itself): (a) `zm_video_regs` at 8 ns, baseline vs the 6-word read; (b) `zm_video_comp`
at 8 ns with `HIER=1`, baseline vs a prototype painter/plane under `prototypes/fresco_re/truecolor/`
(copies, not `fpga/rtl` edits). Results are appended here when they run; until then every figure above
is **est.** from the RTL and the combo7 hierarchy.
