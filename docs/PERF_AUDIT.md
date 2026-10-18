# Perf audit: what a cart costs on KESTREL, without a sim

The Verilator board-SoC sims measure a cart exactly but are two slots shared by every agent,
minutes a frame. The perf suite runs the REAL cart in node (the way `apps/scene_hash.mjs`
does), counts what it executes, and turns the counts into an **estimate** of ZIGGY's
Mc/frame plus a ranked list of the bad patterns behind it. Deterministic: fixed dt, no wall
clock, the same cart gives the same numbers.

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
   op (the CPU spins on BUSY), FRESCO's per-plane pass (0.8 Mc an enabled plane).
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
a D$ model (4 KiB, direct-mapped, 32-byte lines; its misses now cost `DMISS` = 40 cycles in
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

A static op-class finding (`div_loop`, `f64_loop`, `i64_loop`) is now charged what its ops
cost, not the whole loop's time: leonard's Sprite.render loop runs 87K times a frame but its
divide only 1.2K times.

**memset/memcpy on the board (calibrated 2026-10-18).** The board fps of empire (3.7 Mc) and
maxi (5.3 Mc) against the round-2 model (2.48, 2.59) agree on ~86 cycles a 32-bit word of
memory.fill/memory.copy (`FILL_WORD_CYCLES`): a memset is only ~1.5x a byte loop (~31 a
byte store), and a CHISEL fill (~1.85 a byte) is far better. The tutorial board-SoC sim
(0.48 Mc) disagrees (its 51 KB memset would cost ~1.1 Mc at 86): the sim's memory path is
the optimistic one; the board wins.

Waste figures are estimates on top of an estimate: a region's waste is its cycles times the
share of its stores that were redundant.

**The snoop-queue term (a hypothesis).** stcs before perf/board-slow-carts ran 1 fps on the
board; the model said ~13. stcs was the only cart writing far more palette entries in ONE
HBL call (256, every line) than the compositor's 16-entry snoop queue holds, and FRESCO
waits for that queue before each line's pass. `SNOOP_OVERFLOW` (cycles per palette store
past the queue within one handler) is fitted to that single point (1,900): the old stcs
now estimates 1 fps. No other measurement constrains it. It predicts snyd_90 (~7 fps) and
swedish_newyear (~7 fps) are slow for the same reason; a 6-frame board-SoC sim of the old
stcs, or snyd_90 on the board, confirms or refutes it.

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
real-run checks, the byte-loop clear first at 1.5-2.5 Mc, the f64 loop first, determinism.
`--break bytefill` / `--break f64` swap the planted pattern for its twin and pass only if the
checks catch it. `perf_report` prints the shelf's ranking into the gate log and never fails
the gate (the estimate has no threshold stable enough to fail on).
