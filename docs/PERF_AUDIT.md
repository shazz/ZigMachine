# Perf audit: what a cart costs on KESTREL, without a sim

The Verilator board-SoC sims measure a cart exactly but are two slots shared by every agent,
minutes a frame. The perf suite runs the REAL cart in node (the way `apps/scene_hash.mjs`
does), counts what it executes, and turns the counts into an **estimate** of ZIGGY's
Mc/frame plus a ranked list of the bad patterns behind it. Deterministic: fixed dt, no wall
clock, the same cart gives the same numbers.
The typical errors behind those findings, with their fixes and the carts they cost, are in
[BAD_PATTERNS.md](BAD_PATTERNS.md).

```sh
tools/perf_audit.sh <tag|cart.wasm>        # one cart: est. Mc/frame + ranked findings with fixes
tools/perf_audit.sh --all                  # the shelf ranked (~45 s), JSON in zig-out/perf_audit.json
node apps/frame_cost.mjs <cart.wasm>       # the dynamic half alone: classes, hot loops, causes
tools/perf_names.sh                        # (under the build lock) names + file:line for the reports
```

Options (both tools): `--warmup 120 --frames 60` (the steady-state window), `--call F:export:args`
(scripted keys, as scene_hash), `--disk X.zmd` (default: the cart's own disk), `--machine DIR`
(another tree's machine-video.wasm + rom.wasm), `--json`.

## How it works

1. **Instrument** (`apps/perf/instrument.mjs`, a ~150-line wasm rewriter, no dependency). The
   cart and the ROM (both run on ZIGGY, wasm2c'd) get a counter at the head of every
   straight-line segment, in a memory the rewriter ADDS (multi-memory), so no function, global
   or memory index moves. Segment count x its static contents = exact counts of every op class,
   per loop. `memory.fill`/`copy` get byte counters and a log of big fills; i32 stores into the
   palette window compare with the colour already there. hwBlit and HBL dispatch are counted.
2. **Cost** (`apps/perf/cost_model.mjs`). Each wasm op maps to the rv32 sequence wasm2c + GCC make
   of it (`aligned` build): locals are registers, an f64 op is a libgcc soft-float call, a divide
   by a constant is a multiply. Each loop costs max(instructions x CPI, stores x the store buffer's
   drain) -- a tight store loop runs at the drain rate. Plus the I$ working set, CHISEL's time by
   op (the CPU spins on BUSY), FRESCO's per-plane pass (0.59 Mc an enabled plane, plus 0.11 Mc a frame).
3. **Detect** (`apps/perf/lint.mjs`, static, per loop): narrow stores of a constant (`byte_fill`)
   or of a byte just loaded (`byte_copy`), `f64_loop`, `libm_loop`, `table_rebuild`, `div_loop`
   (non-constant divisor), `i64_loop`, `pixel_call` (a call to a small byte-storing function
   per iteration); per function, `float_phase` (a float read-add-written in place). Dynamic only:
   `palette_rewrite` (colour writes of the value already there), `cleared_redrawn` (a big fill
   whose bytes are >= 95 % overwritten in the same frame), `narrow_store_hot`.
4. **Cross-check** (`apps/perf/audit.mjs`): a static finding is ranked by the measured Mc/frame
   of its loop (a libm or pixel call charged its callee's cost); one whose loop never ran in the
   window is `cold`, listed last.

Names: release carts are stripped. `tools/perf_names.sh` builds the same tree with
`-Dnames=true` into `zig-out/perf-names/docs`; the tools use that twin only if its functions
carry the release build's instructions (up to 10 % may differ: LLVM moves a little with debug
info on), and take file:line from its DWARF line table. C carts have no names.

## Waste: only modify what needs to be modified

Every integer store into the VRAM pool is compared, as it happens, with the byte(s) there
at frame START (a snapshot in the counters' memory); fills and copies into VRAM are logged
and compared the same way; after each frame the pool, each enabled plane and the composed
picture are diffed against the previous frame. `--all` ranks the shelf by **wasted
Mc/frame**: the estimated cycles that would go if only what changes were written.

| finding | what it means | fix |
|---|---|---|
| `redundant_store` | a loop (or memset/memcpy) whose VRAM stores mostly rewrite what was there | draw the static page once, dirty rects/rows |
| `clear_then_redraw` | a big fill redrawn in the same frame, all of it or mostly back to what it was | save-under / dirty rects |
| `static_plane` | an enabled plane that never changed in the window | draw once; the dirty-line compositor skips it |
| `lines_changed` | composed lines that changed a frame (`lines`, `dirty` = FRESCO Mc a dirty-line compositor saves) | perf/vseq-dirty |
| `tiny_blits` | blits under 256 B, each paying bblit.c's full D$ invalidate (`BLIT_DFLUSH`) | batch, CPU, or a range flush |
| `scroll_band` | rows that are last frame's shifted by k px, rewritten by the CPU | pan (HSCROLL / FB_BASE), or blit-shift + new column |
| `palette_rewrite` | colour writes of the value already there | write only changes |

**Cycle wastes (round 3).** Probes measure the CPU's own streams: every load runs through
a D$ model (4 KiB, direct-mapped, 32-byte lines; its misses now cost `DMISS` = 48 cycles in
every estimate), costly ops (divides, f64, f32 div/sqrt, libm calls) compare their operands
with their previous execution, i64 arithmetic checks whether its result fits in an i32, and
every branch inside a loop body counts how often it flips.

| finding | what it means | fix |
|---|---|---|
| `div_loop` | divides by a non-constant, executed (not just present) per frame | a hoisted reciprocal or a reciprocal table |
| `recompute` | a costly op or libm call fed the same inputs as its previous execution | hoist it / keep the last result |
| `cache_hostile` | a loop whose loads miss the D$ model, mostly a line or more apart | walk in memory order, transpose, tile |
| `call_in_loop` | a small function called per iteration | inline it, or one call per span |
| `i64_fits_i32` | i64 arithmetic whose every result fits in an i32 | u32/i32 |
| `invariant_branch` | a test inside a loop body that never flips during the frame | test once outside: two loops |
| `misaligned_memcpy` | a memory.copy whose source is misaligned against its destination: the board's memcpy (zm_string.c copy_fwd) builds every word from four byte loads (+9 cycles a word, bench `mis.lw.bytes`; big_demo's 70 KB/frame copy cost the board ~0.1 Mc) | align the source like the destination (`align(4)`/`align(8)` on the buffer or the `@embedFile` copy) |

A static op-class finding (`div_loop`, `f64_loop`, `i64_loop`) is now charged what its ops
cost, not the whole loop's time: leonard's Sprite.render loop runs 87K times a frame but its
divide only 1.2K times.

**Posted stores (recalibrated 2026-10-23).** Since W64 + posted stores the board stores at
~2.26 cycles, whatever the target (VRAM, palette, cart RAM; bench `st.sw/st.sb/st.pal` 256 KB).
A memset runs at that rate a WORD (`FILL_WORD_CYCLES` 2.26), so a byte loop costs its
instructions, not its stores; a memcpy is bound by its loads' D$ misses (`COPY_WORD_CYCLES`
10.95, bench `mc.lib.64K`). CHISEL's ~800 cycles an op (`BLIT_START`) now pay off only on big
fills and copies. The pre-posted numbers (27 a store, 60 a memset word, 693 a misaligned trap)
are history: [the 2026-10-18 fit](#history-the-2026-10-18-fit).

**The snoop-queue term is gone.** `SNOOP_OVERFLOW` fits to 0: a palette store costs what any
store costs (bench `st.pal` 2.16), however many one HBL handler makes.

## Fitted to the board (2026-10-23)

Per-op constants come from the native bench cart (`fpga/tools`, ZMBENCH) run in the SAME board
session as the fps table: prototypes/chisel_queue_re/arms/base/ (2026-10-20, main firmware +
bitstream, W64, posted stores, FPU). Only what the bench cannot measure is fitted, in two stages:

```sh
PERF_NO_CART_ARGS=1 node apps/frame_cost.mjs --all --warmup 720 --frames 300 \
    --machine <that day's docs/> --out calib.json
node apps/perf_fit.mjs calib.json fps.csv --bench --exclude <carts rebuilt since>
```

1. **Cart side**, fitted to the board's measured `cart_c` (cart CPU cycles a frame, uncensored:
   a 60 fps cart tells how long its cart ran too): CPI 1.06, SNOOP_OVERFLOW 0.
2. **Frame**, fitted to frame time with the cart side held: FRESCO_PLANE 0.59 Mc an enabled
   plane, FRAME_BASE 0.11 Mc. The board's compositor probe agrees (`comp_busy` ~2k sys cycles a
   line pass, 280 passes a plane); the bench's `fr.static` (+0.19 Mc a plane) is a static plane,
   which the dirty-line planner skips.

| constant | bench (2026-10-20) | 2026-10-18 fit |
|---|---|---|
| STORE_DRAIN | 2.26 | 27 |
| FILL_WORD_CYCLES / COPY_WORD_CYCLES | 2.26 / 10.95 | 60 / 60 |
| DMISS | 48 | 10 |
| TRAP_CYCLES | 210 | 693 |
| f32 add/sub, mul, div | 9, 10, 21 | 3, 3, 18 |
| f64 add, mul, div | 143, 272, 557 | 90, 110, 450 |
| BLIT_START | 800 | 150 |

Result, 71 carts (rebuilt carts excluded): the 13 carts under 60 fps went from a 38 % median
error (p90 108 %) to 20 % (p90 53 %); the cart side against `cart_c`, 56 carts, from 33 % to
18 %. **The 60 fps knee is now ~1.75 Mc estimated** (60 fps carts: p90 1.62; under 60: median
2.16), against ~2.8 Mc under the old model (the "~3.6 Mc" folklore). Per-cart table:
fpga/review/reports/cost_model_recal_2026-10-23.md.

**The knee is a band, not a line: 1.75-2.1 Mc estimated.** The board shows each frame for whole
VBLs (its probe proves it: frame_ms = 16.6 x (frames + missed) / frames on every cart, within
0.6 %), and in this table no cart missed more than every other VBL (overrun <= 50 %). Under
~1.75 Mc no fitted cart overruns; from ~2.1 Mc most run near 30 fps; between, the probe's `missed`
column decides. Modelling the ceil itself was tried (feat/cost-model-vbl, 2026-10-23) and made
the estimate WORSE: a hard ceil took the sub-60 median error from 20 % to 33 % (misclassified
60/not-60: 7 -> 11), a ceil under a fitted lognormal jitter (sigma 0.21) to 24 % (9), and the
refit's FRESCO_PLANE moved 0.59 -> 0.035 / 0.16 Mc with it: unidentified. A per-frame estimate
good to 20-30 % cannot place a frame on the right side of a cliff; the mean-only model's FRESCO
term absorbs the average overrun instead. Carts the model over-prices near the knee (rno_sodium
2.32, mpp_truecolor 2.57, leonard 2.60 Mc, all 60 fps) are the ones to study next.

Known misses: polkadots_f32 still estimates 28 % low (music, also f32-heavy, 6 % high, so
f32 latency is not refitted on it); mandelbrot/raytrace finish their picture in the node window
but not on the board at 12 s; stniccc streams its disk (DISK_BLOCK is 0).

**The memory-base reload, and CPI 0.88 (2026-10-25).** The cart codegen reloaded
`instance->memory->data` after every wasm store (lw; lw; add before each sw, the loads waiting on the
posted stores). The ZM_LOCAL_BASE A/B (board_fps, 20 s after load; cart_c without -> with the base
kept in a local) measured it: leonard_spirit 1.54 -> 0.77 Mc, stniccc 1.12 -> 0.85, ancool 0.41 ->
0.33, tcb_colorshock 0.58 -> 0.49, union_deltaforce 0.46 -> 0.40, big_demo 0.42 -> 0.27: ~5 cycles a
store on the store-heavy carts (leonard_spirit 158 K stores a frame, stniccc 53 K). The 2026-10-23 fit
had folded that into CPI 1.06, so store-heavy carts read low. With the base local (fc8758ad) CPI
refits to 0.86 on the whole shelf (a card of fc8758ad lean carts, board_fps 12 s after load, 112
carts; cart_c of the 77 over 0.1 Mc, with the FPU twins, stniccc's unpriced disk streaming and the
node-finished mandelbrot/raytrace left out): cart side median error 29% at 1.06 -> 17%, p90 ~84%.
The A/B's six carts alone gave 0.88 (leonard_spirit x0.99 -> est 0.77 Mc). The frame-time stage is
censored (nearly every cart runs 60 fps) and does not identify FRESCO_PLANE, which stays; the budget's
COMP_PASS constants are fitted to comp_busy and do not move. The worst cart-side misses are not CPI:
sysinfo and st_replay (~0 modelled vs 0.57 Mc: ROM/GEM work outside the cart model), dbug (0.29 vs
2.33, a different phase at 12 s), dyno_paradis3 x2.3 and union_superscroller x1.8 high.

**A per-cart CPI miss: branchy byte loops (union_deltaforce, 2026-10-24).** With the base local
(above) its x1.7 is ~x1.4: part of the miss was the reload, the rest stays as described here. The board measured
union_deltaforce's cart at 1.56 Mc (cart_c, 50.8 fps) where the budget said 0.91: x1.7, the same
factor as on its older code (x0.59 the other way, model 2.3 vs board 3.93 Mc, excluded from the
2026-10-23 fit). Not the phase (0.8-0.9 Mc in every window 100-1000), not a stale card; the live YM
the headless run lacks adds only ~0.08 Mc. Compiled as the board builds it (wasm2c, rv32imf), its hot
recolour loop is 13-23 instructions a pixel with three load-to-use chains (wasm2c reloads the memory
base after each byte store) and a data-dependent forward branch taken ~70 % of the time (the static
predictor misses it); 5,768 one-byte memory.copy calls a frame are priced ~24 cycles with no per-call
floor for picolibc's memmove. Those bracket ~0.25-0.3 Mc; ~0.3 Mc stays unexplained. So: on byte loops
with data-dependent branches and store/load interleaving, read the estimate as ~1.7x low; and price a
tiny memory.copy at a real call's floor. The optimized cart (d4c53589, est 0.38) is the test: a board
cart_c near 0.65 Mc confirms the factor is the code shape.

## The frame budget (`--budget`, 2026-10-23)

`node apps/frame_cost.mjs <cart.wasm> --budget`: the cart's Mc of what FRESCO leaves of a frame, with N planes,
~fps, and each plane's line passes and Mc (the costliest marked). FRESCO is counted the way the board's
sequencer issues it (fpga/cycles/vseq.c): 280 passes per enabled plane, plus 280 BG passes when a global handler
prevents the one-command clear, each costed by row width (320 / 400) and first vs later layer (`COMP_PASS`,
`COMP_BG_PASS`, fitted to the board's comp_busy to a 1 % median). The frame is cart + FRESCO, serial: with the
board's measured parts that sum is right about 60 fps for 70 of 71 carts. The dirty-line planner's skips are not
modelled (passes are every line new). Refit: `node apps/perf/budget_fit.mjs calib.json fps.csv`. Report:
fpga/review/reports/frame_budget_2026-10-23.md.

## History: the 2026-10-18 fit

Before posted stores, the model was fitted to 92 carts' board frame times: CPI 1.0,
STORE_DRAIN 27, FILL_WORD_CYCLES 60, FRESCO_PLANE 1.09 Mc, SNOOP_OVERFLOW 240 (snyd_90's 60 fps
refuted the 1,900 the old stcs suggested), median error 4 %.

## It is an estimate

Calibration (2026-10-17): empire's byte-loop clear (~2 Mc a 64,000-byte plane, so ~30
cycles a store at the drain rate), Joust before/after (cart 5.53 -> ~0.8 Mc, 18 -> 60 fps),
compiler-rt sinf (~1,700 instructions) against libm_f32, and the board-SoC sim logs (`ZM AF`
cart cycles, `ZM QF` plane passes):

| cart (board-SoC sim, cart Mc) | sim | estimate |
|---|---|---|
| tutorial | 0.48 | 1.28 (its memset at the board rate, see below) |
| fuji_hobbytronic | 0.76 | 0.77 |
| music_debug (perf/music-board) | 1.82 | 1.95 |
| tsl_hybridglenz | 1.24 | 1.27 |
| raytrace_f32 (frames 2-7) | 6.1 | 4.8 |

What it cannot see: D$ misses (a column walk over a row-major picture), the I$ beyond a
working-set estimate, DDR contention, BARD (music runs there, not in the cart). stcs before perf/board-slow-carts
(1 fps on the board) is matched only through the snoop-queue hypothesis above.

## In the gate

`apps/perf_audit_test.mjs` plants every pattern in a tiny hand-assembled cart
(`apps/perf/fixture.mjs`, `test_cases.mjs`) and its clean twin in another: static and
real-run checks, the byte-loop clear first at 0.3-0.7 Mc (instruction-bound since posted stores), the f64 loop first, determinism.
`--break bytefill` / `--break f64` swap the planted pattern for its twin and pass only if the
checks catch it. `perf_report` prints the shelf's ranking into the gate log and never fails
the gate (the estimate has no threshold stable enough to fail on).
