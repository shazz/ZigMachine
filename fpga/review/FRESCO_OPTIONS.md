# FRESCO: where a line pass goes, and four ways to take it off the frame (2026-10-23)

Study for the lead (perf/fresco-study). Board: Z7-Lite, bitstream d649cd0e, glass c0b53033; firmware
built from this branch (origin/main 8ddd9782), bind-mounted from RAM and removed after. Cycles are sys
(100 MHz) unless marked comp (125 MHz, 0.8 sys). "Mc" = millions of sys cycles; a 60 Hz frame is 1.67 Mc.

## A. Where a line pass's cycles go

Three sources agree: the board's boot calibration VCAL (`cycles/vcal.c`, four MIX/FILL passes on line 0),
the RTL compositor replayed on recorded frames with a phase counter (`tools/video_phase.py`, new: clocks
in each state of `zm_video_pass.v`, memory a beat a clock), and the board probe (`comp_busy`, `passes`).

| phase | comp clocks | sys | source |
|---|---:|---:|---|
| row LOAD, 400 beats (PFB or picture) | 528 | 422 | VCAL: MIX2 - MIX1 = 2192 - 1524 (FILL2 - FILL1 agrees) |
| row STORE, 400 beats | 484 | 387 | VCAL: FILL1 - MIX1 = fill + W - R |
| fixed per pass (CDC, FSM, AXI B wait) | ~171 | ~137 | VCAL MIX1 - R - mix - W |
| fill (CLEAR colour, 800 px) | 403 | 322 | phase tb |
| plane fetch, 41 / 51 beats + latency | ~170 / 180 | ~140 | phase tb + VCAL latency |
| paint, 320 / 400 columns | 329 / 408 | 263 / 326 | phase tb |
| mix (2 px a clock) | 406 | 325 | phase tb |

Check: union_main plane-major (3 overscan planes, first fused) = (fill + fetch + paint + mix + 2W + o) +
2 x (2R + fetch + paint + mix + 2W + o) = 2536 + 2 x 3189 comp, 2377 sys a pass; the board measures
**2362** (0.6 %). So a later layer's pass is **~60 % row I/O** (2R + 2W = 2024 of 3189 comp), 30 % paint
and mix, 10 % fetch/fixed. The row I/O runs at one beat per SYS clock (the HP port), so the 125 MHz comp
clock does not help it.

CPU side (board probe, `seq_c - ready - drain - painted - hbl - plan - swap`): 190-450 sys of
bookkeeping a pass, mostly hidden under the pass: the compositor is idle only ~110 sys a pass inside the
sequencer on handler-light carts (union_main 0.10 Mc a frame). **HBL entry**: 160 sys a call for a
flicker-only handler (supplex_fs2), 320 for flicker + 1 entry (union_main); a handler's stores cost
~28 sys each (posted, DDR-bound), so tcb_colorshock's 105 palette words are **2,980 sys a line, 0.83 Mc
a frame**, of which ~0.57 Mc leaves the compositor idle. Fresh board probe: `fpga/build/board_fps_base/`.

## B. The options

Representative carts (board, this card): union_main 29.3 fps (cart 1.32 + FRESCO 1.98 Mc), supplex_fs2
30.3 (0.55 + 1.98), tcb_colorshock 30.1 (0.25 + 1.26 + 0.83 handler), replicants 30.1 (0.23 + 1.69),
union_l16 38.6, stniccc 41.7 (1.48 + 0.37), leonard 59.4 (0.69 + 0.69, already one group). ancool is now
one normal plane (200 passes, 0.38 Mc) and at 60.

### 1. Composite at scanout (beam-racing)

Saves **all** of FRESCO from the frame: union_main / supplex 1.98 Mc, replicants 1.69, colorshock 1.26,
leonard 0.69, stniccc 0.37; removes both 875 KiB pictures and every row store (DDR traffic down to the
plane fetches). Throughput fits: a raster line is two 800x600 scanlines = 6,600 comp clocks, and four
planes need ~4 x (fetch + paint + mix) + fill = ~4,400. Cost: a per-line, per-plane state log (palettes,
HSCROLL, RESOLUTION, RES_FLICKER), because handlers would run ahead of the beam and their writes replayed
at scanout; a line buffer per plane; estimated +800-1,500 LUT and +4-8 RAMB36 against a board build at
~15,000 of 17,600 LUT. Timing: a hard deadline per line where today there is none.
**This is an architecture fork**: it reverses the 2026-10-02 ADR (Fable #1: composite at the
compositor's speed in the machine's order, scan out the previous frame); carts draw in place into the
LFBs the beam would read during the next frame() (needs double-buffered LFBs: a cart ABI change), and the
line-major order it imposes is the one that broke badflicker and equinox. **Stop here: Matt / Fable.**

### 2. Overlap FRESCO with the cart

The output is already double-buffered (two pictures, PRESENT at VBL); what serializes the frame is the
INPUT: frame() N+1 draws into the LFBs and palettes that frame N's passes still read, and the CPU itself
runs the sequencer and the handlers. Exact overlap needs (a) the cart to flip its LFBs each frame (an
opt-in ABI: "frame() never touches what the last frame showed", with no hardware check short of a
store-hazard scoreboard on ZIGGY's write path), (b) double-banked palette/register copies in the
compositor (+1 RAMB36), (c) a hardware pass sequencer (PLANES_PLAN option 8, ~300 LUT) and (d) no plane
handlers (they are cart code on the same CPU). Saving: frame = max(cart, FRESCO) instead of the sum,
i.e. min(cart_c, FRESCO): leonard 0.69, stniccc 0.37, union_main 0.85 after option 3a. Medium-to-high
risk, a cart ABI change, and it only reaches handler-free carts. **Not now**; a fork too if pursued.

### 3. Copper list: two halves with separate numbers

**3a. Pure handler planes join line-major groups (firmware only, built and measured).** A plane with an
HBL handler is plane-major today (cycles/bplanes.c) because its handler could write what another plane's
pass reads. The handler census over the shelf (all 106 carts + C/Rust) finds **54 carts whose every
handler is pure**: it writes only its own plane's palette and/or calls flickerBorder(), reading tables
and frame()'s scalars. Such a handler can run right before its own pass of each line, inside a group, as
video.zig runs it, with ONE exception: RES_FLICKER is one register for all planes, and an overscan pass
flickers when it differs from what that plane last saw. `cycles/vseq_group.c` now reads RES_FLICKER around
each handler (video.zig's own before/after) and stores, before the pass, the value that gives the plane
its own answer; after the group, the true count. This is what Matt's copper list buys in rows moved,
with no RTL: the list's other half (3b) is the handlers' CPU time.

Board A/B, same card, same carts, firmware A = this branch as main behaves, B = every handler trusted
(`ZM_GROUP_HBL_ALL`, the experiment; `fpga/build/board_fps_{A,B}/`):

| cart | fps A -> B | FRESCO Mc (comp_busy) A -> B | frame Mc A -> B |
|---|---|---|---|
| union_main | 29.3 -> **40.0** | 1.98 -> 0.85 | 3.43 -> 2.48 (the rest is cart: 1.32) |
| supplex_fs2 | 30.3 -> **60.2** | 1.98 -> 0.85 | 3.31 -> 1.65 |
| replicants | 30.1 -> **60.2** | 1.69 -> 0.70 | 3.31 -> 1.65 |
| tcb_colorshock | 30.1 -> **52.5** | 1.26 -> 0.64 | 3.31 -> 1.95 (handler 0.85 Mc left: 3b) |
| union_l16 | 38.6 -> **46.3** | 1.27 -> 0.64 | 2.81 -> 2.61 |
| automation442 | 60.2 -> 60.4 | 1.27 -> 0.63 | swap wait 0.16 -> 0.74 Mc (headroom) |
| deltaforce | 60.2 -> 60.2 | 1.14 -> 0.54 | swap wait 0.25 -> 0.83 Mc |
| stniccc | 41.7 -> 41.9 | 0.37 -> 0.37 | no handler: unchanged (control) |

Once its handler is flagged pure, a one-plane handler cart would also lose its PFB row store (a group on top:
`nopfb`), ~0.11 Mc (B does this for every such cart; production does not until the flag exists).
Cost: 0 LUT, 0 BRAM, no bitstream; ~1 KB of firmware. Timing risk: none.
Exactness: the RTL replay of the group order with the firmware's RES_FLICKER (`tools/video_order_group.py
--all --fw`) MATCHes the machine on union_main, supplex_fs2, union_l16, tcb_colorshock, automation442,
replicants and deltaforce (frames 300 and 600), and on the synthetic `overscan` frames whose four planes
flicker on different lines, which DIFFER without the store (the break). `tests/test_vseq_group.py` runs
vseq_group.c itself against an RTL model of the flicker test (and its break, ZM_RTL_BREAK=1).

**Open before the ABI lands: the pixels of B on the board.** The proofs above run the tool's model of the
store, or the C against a model of the RTL; nothing has replayed the firmware's own stores through the
compositor, and the A/B measured speed only. The override relies on the `before`/`now` loads seeing the
handler's posted store through the write-through D$ (the first load caches the line, so the store hits
it: reasoning, not evidence). Proof to run: one hp_sim slot, <= 6 frames, supplex_fs2 with
`ZM_GROUP_HBL_ALL` and a picture hash of a line-major frame against vmix (bplanes_check_pre refuses
handler planes, so the pure case needs its own hook: pure handlers may run twice), or a board_shot
picture diff A vs B on a static frame.

What is NOT done, and needs a decision: the firmware must KNOW a handler is pure. B trusts every handler,
which is wrong for carts whose handlers talk (bladerunners, vex: global <-> plane; mpp_truecolor and
fujiboink keep state with frame()). Proposed ABI: `REG_FB_HBL_PURE` (u8 x 4 at 0x74, free), set by the
library installers (`openBorders`, `copper.install`, `linepal.install`) and by a new
`setFrameBufferHBLHandlerPure()` for the custom pure handlers (union main/runner/scroller, supplex,
replicants, colorshock's panHbl...), ignored by video.zig (the browser order stays the reference), HW 1.8.0;
a gate harness runs `video_order_group --all --fw` on every flagged cart and fails on DIFFER. Matt's carve
("HBL stays for racing the beam: overscan flicker") is kept: the flicker stays a CPU handler; only the
sequencer learns it may interleave it.

**3b. Hardware copper list (Matt's decision; the CPU-time half).** A per-plane list (pointer + count a
line, latched at LATCH) the compositor fetches through its read port and applies to the plane's palette
RAM before PAINT; zg.copper / zg.linepal (and colorshock-style blocks) compile to it, so the CPU runs no
handler and makes no palette stores. Saving = the `hbl` column where it is exposed: tcb_colorshock 0.83
Mc (-> 60 fps with 3a), swedish_newyear 0.46 (its global raster also needs a BACKGROUND list), union_main
0.27, dune_gen4 / snyd_90 / replicants_emlyn (16-149 entries a line). Per-line cost in FRESCO: one burst
(~130 comp latency + n/2 beats) plus n palette writes, hidden under LOAD on a first-layer pass.
Estimate: +200-300 LUT (list FSM, a second palette write port, per-plane pointer/count), 0 BRAM; baseline
`zm_video_comp` OOC synth 1,775 LUT / 1,456 FF / 15 BRAM tiles / 13 DSP, WNS +1.03 ns at 8 ns, so timing
risk is low. ABI: new machine registers + video.zig applying the list (both machines), palettes written
back to the region at frame end (copper.hbl reads them back today), HW minor bump. Do 3b after 3a: 3a
gives the grouping; 3b then removes CPU time from the carts that still miss.

### 4. More dirty-line skipping

Last, per Matt (content-dependent, not deterministic). Not costed.

## Recommendation

1. **3a now** (lead + Matt: the ABI byte and the harness): +10 to +30 fps on the five slowest multi-plane
   carts, no RTL, measured on the board; the firmware is on this branch behind the experiment switch.
2. **3b next**, scoped to the handler-heavy carts (colorshock, swedish, dune, snyd, emlyn).
3. **1 is a fork** (ADR reversal, cart ABI): Matt decides whether Fable looks at it. **2** only with 1's
   ABI question settled.

Reproduce: `uv run python tools/video_phase.py <cart> <frame> --timing 0 [--fuse] [--line-major [--nopfb]]`;
`uv run python tools/video_order_group.py <cart> <frame> --all --fw`; board A/B: build
`make ZM_AUDIO=snd ZM_FPU=1 [HRV_CFLAGS_EXTRA=-DZM_GROUP_HBL_ALL] build/hcycles/split/board_snd_fpu/sys.bin`,
stage with `glass_shelf.stage_system`, bind-mount over `/mnt/sd/zigmachine/system.rv32`, `killall glass`,
`tools/board_fps.py --tty /dev/ttyUSB1` (prototypes/fresco_re/).

## Decision 2026-10-24

Lead and Fable (Matt delegated): **stay frame-serial.** Land 3a (pixel proof on the board first:
done, the board's pictures equal the browser's on 20 frames of the five carts), then 3b, then
SOC_REVIEW F3 (RGB565 + alpha rows) and F2 (scanout underrun counter) for bandwidth. Idea 1 is not
opened: the board build is at 94 % LUT with sys WNS +0.04 ns, a slow line would be on-screen garbage,
and it loses the scene_hash oracle. If double-buffering is ever paid for, it is for idea 2.
For 3b: a list word format with room for non-palette registers (RES_FLICKER, HSCROLL) so it never
needs rewriting; palettes written back to the region at frame end (copper.hbl reads them); the list
fetch hidden under LOAD on first-layer passes; OOC synth and comp-domain timing before any bitstream.
After 3a + 3b: count the carts still FRESCO-bound on the board (cart_c <= 1.67 Mc and cart_c + seq_c
> 1.67 Mc), and run F3's AXI beat counters and F2's underrun counter on one 3-plane frame.
