# perf/chisel-async: CHISEL's lazy wait (option 1, no RTL change)

Branch `perf/chisel-async` from origin/main `f635ed98`, worktree
`.claude/worktrees/chisel-async`. Full gate green (261 harness jobs, every scene_hash unchanged).
Board stage: `prototypes/chisel_async_re/stage/` (INSTALL.txt). Nothing measured on silicon yet.

## 1. Where every CHISEL path waited

There is exactly one wait on the board: `fpga/cycles/bblit.c` `blit_rtl()` (now
`fpga/cycles/bchisel.c`), the `--wrap` of the machine's `hwBlit`. Every driver goes through it:

| Path | How it drives CHISEL | Waited |
|---|---|---|
| `libs/zig/blitter.zig` (`zg.Blitter`: fill, line, triangle, bob, blitImage...) | registers (store only on change) + `hw.hwBlit()` per op | in hwBlit |
| `libs/zig/chisel.zig` (ZigOS's own: `clearFrameBuffer`, `blit.Dst.fill` >= 256 B, blit copy ink, `sprite_draw`) | save regs, op in runs per clip window, restore regs | in hwBlit |
| Carts' own drivers: `stniccc/gpu.zig` (one FILL per span), `gen4_3615/chisel.zig` (D = A & B) | raw registers + `hwBlit` | in hwBlit |
| ROM (`rom/`), C and Rust bridges | none drive CHISEL today | - |
| Native bench (`cycles/native/bench/chisel.c`) | `hwBlit` through the sys table, or GO + poll directly (`ch.raw.*`) | in hwBlit / its own poll |
| The machine's software blitter (D below OFF_VRAM, before VBASE) | CPU stores | synchronous by nature |

Where a wait is really needed (each is now a sync point):
- **The next op's registers.** `zm_blit_regs.v` drops every register store while BUSY (`wr_ok = !busy`),
  and the cart writes registers as plain stores the firmware never sees. This is the hard reason the
  default had to stay synchronous. Fixed by a replay: after a lazy op, every word of the block is
  stored back through the tap from memory.
- **CPU access to source/destination pixels.** Invisible to the firmware (wasm2c loads/stores). Only
  the cart can promise it: hence opt-in.
- **D$ lines of the destination** must be dropped after the op (bdinval.h). Planned at GO, applied at
  the sync (the registers may describe the next op by then).
- **CYCLES/STATUS readback**, the compositor (end of `frame()`), HBL handlers (they run mid-composite),
  the ROM (draws with the CPU), the drive (may overwrite a source).

## 2. Where the ~900 cycles go (8x8 fill, posted stores, BENCH_REPORTS)

- `ch.raw.fill8.x64` = 544: the cart's register compares + 1 store + GO + spin. So **~450-500 cycles
  are the wait** (GO to BUSY low: the tap, the drain, the op's AXI read/write round trips, 64 px).
- `ch.fill8.x64` = 911 through hwBlit: **~370 are the wrapper** (table call, VBASE CSR read, D_BASE and
  COMMAND loads, the box and 8 row invalidates, CYCLES/STATUS).
- A big op adds ~1.03 c/B fill, ~1.3 copy, all of it wait.

The lazy wait hides the wait part only, and only behind CPU work done before the next sync. It does
not touch the ~370 of wrapper, and adds ~80-100 per lazy op (the replay: 24 loads + 24 posted stores).

## 3. What moved

- `machine/sdk/memmap.zig`: `BLIT_ASYNC = OFF_BLIT + 0x64` (0xE4, u8). Outside the tap's 24 words
  (0x80..0xDF) and every snoop window; the machine never reads it, so the browser cannot change.
- `fpga/cycles/bchisel.c/.h`: GO, then with `BLIT_ASYNC` one uncached load (closes the held-start race:
  a DDR store right after GO could make the tap hold the start while later register stores still get
  in), the op's D$ plan, and return. Sync = wait, `bdi_apply(that plan)`, CYCLES/STATUS, replay. A
  waited op plans after the wait, as before, and the after-lazy path is out of line, so the common
  path makes no call (test_blit_path's budget: a few bus writes a call).
- `fpga/cycles/bdinval.h`: `bdi_range` split into `bdi_plan_op` + `bdi_apply` (same text for every
  break mutant of test_blit_dcache, all still caught).
- `fpga/tools/host_gen.py` / `host_split.py`: `HOST_CHISEL_SYNC()` before every machine/ROM env entry
  but hwBlit, after every HBL dispatch, before the drive; no-op natively, `-include bchisel.h` on the
  board (board.mk/split.mk). `bmain.c`: sync at the end of `frame()` and before compositing.
- `libs/zig/chisel_async.zig`: `setAsync(base, on)` (off syncs first: off always means nothing pending),
  `sync(base)` (a NOP hwBlit, COMMAND put back), `isAsync`. `Blitter.setAsync/sync`,
  `ZigOS.blitAsync/blitSync`; `Blitter.cycles()` syncs first.
- Carts (read op by op for the contract):
  - **fuji_hobbytronic**: the plane clear overlaps the logo's turn/cull/sort (`logo.prepare`, no pixel
    touched); then each triangle's setup overlaps the last fill. Stars/title/scroller synchronous.
  - **tsl_hybridglenz**: stage fills, glenz triangles (projection overlaps the inner fill), logo, bar;
    the CPU scrolltext syncs first.
  - **stniccc**: each span's fill overlaps the next span's edge walk; the keyframe save/restore (CPU
    copies of the plane) sync first (`polyfill.Target.sync`); the blinking message is synchronous.
- Bench (`tests_async.c`): `as.seq.*` vs `as.lazy.*` for a 64 KiB fill + 48000 ALU ops or 24576 word
  stores, an 8 KiB fill + 6000 ALU ops, 64 8x8 fills back to back (`f8`) and with 256 ALU ops between
  (`f8w`); `as.kick.64K`, `as.sync.64K`, `as.sync.idle` timed alone.

Tests: `fpga/tests/test_chisel_async.py` (host model of engine + tap, writes dropped while BUSY; 7 rules;
`ZM_RTL_BREAK=1`: no replay, plan at sync, no wait at the next op, always lazy: all caught),
`test_blit_dcache.py` (with breaks, core tests on the board's VexRiscv), `test_blit_path.py` (now
links bchisel.c; with its break), `test_host_gen.py` (new hook test), `test_native_bench.py`. Full gate green. `test_bench_collect.py` has 3 failures that are the same
on the base (no devmem on this box).

## 4. Expected (predictions, not measured)

| Row | sync (today's model) | lazy (predicted) |
|---|---:|---:|
| as.seq/lazy.alu.64K | ~67K + ~66K = ~133K | ~68K (x1.9) |
| as.seq/lazy.st.64K | ~67K + ~55K = ~122K | ~68K (cn.st.fill: stores unaffected) |
| as.seq/lazy.alu.8K | ~9K + ~8K = ~17K | ~9.5K |
| as.seq/lazy.f8.x64 (per op) | ~911 | ~900-950: no work to hide behind, the replay costs ~90 |
| as.seq/lazy.f8w.x64 (per op) | ~911 + ~350 | ~800-850 |
| as.kick.64K | - | ~350-450 (wrapper + plan + GO + barrier) |
| as.sync.idle | - | ~100-150 (a NOP hwBlit) |

Carts (op counts from `tools/perf_audit.sh <tag>`, the browser run of frames 121..180):
- **stniccc**: **1014 blits a frame** (1001 under 256 B). Board today: 41.1 fps, cart_c 1.33 Mc. At
  ~911 a call that is ~0.92 Mc in hwBlit, so the rest of the cart averages ~400 cycles of CPU per op.
  Hidden per op ~ min(~450 latency, CPU before the next sync) - ~90 replay ~ up to ~360:
  **~0.15-0.37 Mc a frame back**, frame ~1.94 -> ~1.6-1.8 Mc, i.e. **~44-50 fps** (the low end if the
  spans of one polygon follow each other with little work between, which is likely for the big ones).
- **fuji_hobbytronic**: 127 blits a frame (122 triangles under 256 B, the 64 KB clear). 60 fps already
  (cart_c 0.83 Mc): expect cart_c down by the clear (~66K, behind the logo maths) plus part of each
  triangle's latency, ~50-100K in all. No fps change (vsync-capped).
- **tsl_hybridglenz**: a few dozen big ops (fills, glenz triangles, logo blits; perf_audit's model
  gives the blitter 48 % of its estimate). 60 fps already (cart_c 0.18 Mc on the board): cart_c only.

The synchronous path itself (every cart that does not opt in): on the board-core model of
`tests/test_blit_path.py` (blocking stores, 16 cycles each) an 8x8 FILL through hwBlit is 341 cycles
and 2 bus writes against 316 and 1 on the base: one saved register (`ra`) and the pending check. On
the board with posted stores that is ~+5 cycles of ~911.

Other candidates, not adopted (each needs its frame reordered or a CPU path proven off the op's pixels):
union_tnt1 (32 fps: kick the clear in update() before the ball physics), gen4_3615 (19 fps, CHISEL and
CPU interleaved), polkadots (reads CYCLES after every op: it would sync each time), blitter_demo (a
`printText` inside its effects).

## 5. Option 2 (a CHISEL command queue) after this

Still worth it, more clearly than before. The lazy wait only pays where the CPU has its own work
longer than the op's ~450-cycle latency before it needs CHISEL again; the many-small-ops carts
(stniccc's spans, every triangle-per-face 3D cart, bobs) pay the ~370 wrapper + the latency on every op,
and lazy can only hide part of the latency (plus it costs the replay). A descriptor queue that CHISEL
drains on its own makes an op ~6-8 posted stores (~20 cycles) for the CPU, removes the
register-drop hazard (the engine reads descriptors, not live registers), and lets the D$ invalidate
be one range at the sync instead of per op. For ~1000 ops a frame that is ~0.8 Mc of CPU back.
What the board should confirm first: `as.kick.64K` (the CPU floor of today's call path) and the
f8 vs f8w rows (how much of the 450 is CHISEL-side startup that a queue would not remove). A cheap
software step before the RTL: a firmware batch call (N register sets in cart RAM, one hwBlit) that
removes the table call and wrapper per op but not the latency.

## Risks

- Contract violations draw wrong on the board only (never in the browser or the gate). The three
  carts were read for it; any future cart that opts in must be read the same way.
- A cart that sets BLIT_ASYNC and reads `BLIT_CYCLES` directly (not `Blitter.cycles()`) gets the
  previous op's value until the sync.
- The replay assumes memory always holds the cart's intended registers (true: the machine reads
  memory) and that the tap never takes COMMAND from a region store (zm_blit_soc.py: `o_sel & 0b1110`).
- The held-start barrier relies on the in-order core stalling on the uncached load (VexRiscv: yes).
- Every machine/ROM env entry now costs a load and a branch (~3 cycles) when nothing is pending.

## Board result (2026-10-19, lead; lm8 bitstream, old order, glass --fw-opt=0)
- Big ops overlap as designed: as.seq.alu.64K 133K -> lazy 68K (x1.97); as.seq.st.64K 122K -> 67K; 8K 17.8K -> 10.0K. as.kick.64K = 577 cycles, as.sync.idle = 277.
- Small ops get SLOWER lazy: as.f8.x64 56.3K -> 62.6K (+98/op), as.f8w.x64 79.4K -> 85.5K (+96/op): the register replay costs more than the ~360 cycles of CPU work hides.
- ch.fill8.x64 911 -> 944/op?? no: 64403 -> 60403 total (the new wrapper is ~60 cycles cheaper for sync callers).
- fps: stniccc 41.1 -> 34.6 (REGRESSION, small spans), fuji_hobbytronic 60, tsl_hybridglenz 60, union_tnt1 60 (all unchanged).
- Verdict: keep lazy only for big ops (clears / big copies); drop stniccc's opt-in; the many-small-ops case needs option 2 (command queue).
