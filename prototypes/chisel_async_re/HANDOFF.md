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
- ch.fill8.x64 64403 -> 60403 for 64 ops (sync callers: the new wrapper is ~60 cycles an op cheaper).
- fps: stniccc 41.1 -> 34.6 (REGRESSION, small spans), fuji_hobbytronic 60, tsl_hybridglenz 60, union_tnt1 60 (all unchanged).
- Verdict: keep lazy only for big ops (clears / big copies); drop stniccc's opt-in; the many-small-ops case needs option 2 (command queue).

## 6. Option 2 built: the CHISEL command QUEUE (HW 1.8.0), 2026-10-19 evening

Commits on perf/chisel-async: 1304c861 (stniccc async opt-in dropped) .. ae20c9ea. Stage:
`prototypes/chisel_async_re/stage_queue/` (INSTALL.txt, MD5SUMS.txt). NEW bitstream + NEW system.rv32:
install both (the firmware no longer replays registers; only right on this RTL).

**Choice: a snooped on-chip ring, not a DDR list.** The cart stores descriptors into a 512-word ring
in the region (OFF_BLIT_QUEUE = 0x1DC000, above the BEAM table, outside REGION_BYTES); CHISEL's tap
copies every store into a RAMB18 the same way it copies the block. Correct by construction: the ring
stores and the GO go through the same in-order tap, so a list is in CHISEL before its kick; CHISEL
can only read what the cart stored into its own ring (no bounds check, no M-only DDR leak); no
read-port arbiter against the pixel unit and no AXI round trips per descriptor (~2 clocks a word
from BRAM vs ~45-90 a descriptor from DDR, which would have made CHISEL the bottleneck at ~1000 ops).
Cost: one BRAM tile, a 21-bit compare in the tap. The DDR list's only edge (unbounded length) does
not matter: lists are kicked per half-ring (256 words).

**Registers are never dropped any more.** zm_blit_regs: a TAP bank (LUT RAM, 4 byte lanes, every
store, also while BUSY = memory's block) and the OP bank the engine reads. zm_blit_q copies tap->op
at every kick (24 clocks) and then runs one op or the list (header = mask of block words + COMMAND,
words lowest first, each op to its end before the next header). BLIT_WINDOW holds a READ while a
store is in the tap or the copy runs, so the firmware's load after GO is the barrier. No replay
anywhere (the lazy single-op path loses its +98 cycles too).

**Semantics (machine = browser = native host, machine/blitter_queue.zig):** COMMAND 5 with
Q_START/Q_COUNT (block 0xE8/0xEA); ops on a working copy of the block taken at the call; the block
left as it was; CYCLES = sum; refused (CYCLES 0) for an empty list or one past the ring; a descriptor
cut short ends the list unrun; COMMAND 0 only sets words; a nested 5 is an unknown op. ZM_HW_VERSION
1.8.0. docs/BLITTER_HW_SPEC.md §6/§10.1, HW_API.md, guide regenerated.

**Firmware (bchisel.c):** a QUEUE is always lazy (GO word = 5 | start<<8 | count<<17, refused like the
machine); its sync sweeps the whole D$ once per list (a list may touch the whole plane; a 4 KiB D$
sweeps anyway past 128 lines) — correct by construction (a superset of the union). The next kick
waits for the previous list (double buffer by ring halves).

**ZigOS:** `zg.blit_queue.Queue` (op/set/fill/kick/flush) over `effects/blit_list.zig` (pure, tested
natively): a word goes in the ring only when the list's working copy does not hold it, the block is
never written, and the words the queue's ops set (`owned`) are restated at the head of every new list
(after an auto-kick or a flush), since every list runs on a copy of the block, which never saw them.
A direct hwBlit made while a list is being built runs before it (both machines): flush first.
Contract: a queued op's pixels are only drawn for sure after flush(). Plus `zg.chisel_copy`
(copy/copyQueued, ZigOS.copyMem): CPU below COPY_MIN = 4 KiB, CHISEL above (dest VRAM, source in a
readable window, no overlap), the lead's 19 Oct crossover table in its comment. The system libc
memcpy is NOT switched (it would have the firmware write the cart's block behind its back and wait
inside machine-internal copies).

**stniccc:** begin() puts D_BASE/D_STRIDE/MINTERM/CON into the list; each span is a queued fill;
keyframes and clearPlane flush; drawFrame flushes before the CPU's text. --only stniccc gate green.

**Pixel proof, and a gate hole found on the way.** The stniccc gate job (apps/stniccc_headless.mjs)
takes PPM shots and times frames; it hashes nothing, so it cannot catch a wrong pixel. The first
library version passed it while drawing wrong: it reseeded each list from the block, so after a
mid-frame auto-kick, or the keyframe flush during the rewind, the spans lost the destination set()
had given (frames 754..865 differed). Proof used instead: scene_hash.mjs every frame for 2400 frames
(small, rewind, message, zoom, fullscreen) of this cart against the pre-queue cart (1304c861):
IDENTICAL (84c2f7961a191a7b). blit_list_test.zig pins the fix (in build.sh). Worth a golden
scene_hash for stniccc in the gate.

### Vivado (board recipe, main's RTL, fpga/build/board_queue)
- 15,188 LUT (86.30 %), 15,437 FF, 42 BRAM tiles (+0.5: the ring). zm_blit 3,662 LUT vs 3,436 in
  board_lm8 (+226, of which ~32 LUT RAM for the tap bank). Baseline posted build 15,045.
- All constraints met: sys (clkout0) WNS +0.133 ns, comp (clkout1) +0.069 ns, others +1.178/+0.574.
- CSR map byte-identical to board_lm8 (itself identical to 3ebb7381): table 1.2, every lean cart runs.
- Line-major NOT merged: `git merge-tree` with 600e6cbd conflicts only in decisions.md, but it brings
  its own firmware/glass (fw-opt) unproven on silicon; this bitstream is main's RTL + the queue.

### Tests
- test_rtl_blitter.py: 14 pass (fast/random/deep x edges, random1/2, queue1 vs the machine; random
  mode now stores the next op's registers early while BUSY). ZM_RTL_BREAK=1: 55/55 mutants caught
  (11 new: store dropped while busy, op bank not loaded, list from the last op, BLIT descriptor
  skipped, two ops at once, words highest first, idle before the list ends, count off by one, read
  past the count, cost not summed, word 0 drops CON).
- test_blit_queue_soc.py (Migen, new) + test_blit_soc.py: 12 pass (ring forwarding, GO word range,
  read hold; `ring` and `nohold` mutants).
- test_chisel_async.py: 12 cases, 8 mutants caught. test_blit_path / test_blit_dcache with breaks:
  pass (8x8 FILL through hwBlit 344 cycles on the core model, was 341). test_native_bench: 13 pass.
- apps/blitter_queue_check.mjs (in build.sh): 3 x 60-op lists draw what their ops draw one by one,
  block restored, CYCLES = sum; the edges. chisel_copy_test.zig (in build.sh).
- --only stniccc gate green (EXIT 0, 5 harness jobs). test_blit_hp_order, test_blit_wburst,
  test_prim_allowlist, test_sound_regs: 34 pass. bench_contention's raw GO path stores no block
  register between GO and its wait (checked): its rows do not move.

### Predictions (to be measured on the board)
| Row | sync | queued (predicted) |
|---|---:|---:|
| 64 x 8x8 fill | as.seq.f8.x64 56.3K | qu.list.f8.x64 ~10-13K (CHISEL ~150/op in a list) |
| same, 256 ALU between | as.seq.f8w.x64 79.4K | qu.list.f8w.x64 ~25-28K (CPU-bound: ~360+40/op) |
| 64 x 16x16 fill | qu.sync.f16.x64 ~75K | qu.list.f16.x64 ~25K |
| 64 x 8x8 / 16x16 copy | qu.sync.c8/c16 ~65K/~85K | qu.list.c8/c16 ~16K/~30K |
| 256 spans + 140 ALU | qu.sync.span.256 ~280K | qu.list.span.256 ~50-55K |
| build+kick 64 fills | - | qu.kick.f8.x64 ~3K (the CPU's price: ~40/op + ~600/kick) |
| switched copy | cp.lib.2K ~2K, cp.chisel.4K ~6K | cp.sw.2K = cp.lib.2K, cp.sw.4K/8K = cp.chisel |
| lazy small ops | as.lazy.f8.x64 was 62.6K | ~as.seq.f8.x64 or below (no replay) |

stniccc: ~1014 spans at ~911 cycles (~0.92 Mc of cart_c 1.33 Mc) become ~40-60 cycles of ring stores
each plus ~12 kicks (+ a D$ sweep and refills each, ~20K): cart_c ~0.45-0.5 Mc, CHISEL ~0.15-0.2 Mc
of its own behind the edge walk. **55-60 fps predicted** (41.1 before; vsync-capped at 60). The floor,
if CHISEL turned out slower per op than predicted: still one kick per half-ring, ~0.6 Mc, ~50 fps.

### Which other carts should take the queue
- gen4_3615 (19 fps; CHISEL and CPU interleaved, many small D = A & B ops): biggest candidate.
- fuji_hobbytronic (122 small triangles/frame) and tsl_hybridglenz (glenz triangles): cart_c only
  (60 fps already).
- union_tnt1 (32 fps) only if its ops are small; polkadots no (reads CYCLES after every op);
  bob/tile carts through Blitter.bob / blitImage once a queued variant exists (not built).

### Risks
- A cart that touches a queued op's pixels before flush() draws wrong on the board only.
- QUEUE is always lazy: every machine/ROM call in the cart's build loop waits (a call per span would
  serialise; stniccc calls hwVideoBase once per begin()).
- The read hold on BLIT_WINDOW also delays STATUS polls during a kick's 24-clock copy (harmless).
- Byte-enable BRAM (the ring) is "suspect" under openXC7 only; the board flow is Vivado.
- Not run: hp_sim of a queued cart (no SoC sims today). First board run is the proof.

## 7. Board results for stage_queue (lead, 2026-10-19 23:10) and the diagnosis (WIP, not merged)

Raw: `.claude/worktrees/int127/fpga/build/bench_lm/queue/bench_20261019_231027.txt` (bitstream e237ff42,
system e1a6e84a, glass --fw-opt=0). NB: the staged sd/demo-bench.zmd was the 2 KB browser stub; the lead
rebuilt it (`make native-cart NAME=bench ZM_FPU=1` + glass_sd fattening). Fix the staging next time:
take the bench disk from glass_sd's output, not build/hcycles/split/native_fpu/bench/disk.zmd.

| Row | Board | Predicted | Sync on the board |
|---|---:|---:|---:|
| qu.list.f8.x64 | 31.6K | ~10-13K | as.seq.f8 58.4K |
| qu.list.f8w.x64 | 54.8K | ~25-28K | as.seq.f8w 81.5K |
| qu.list.f16.x64 | 43.9K | ~25K | qu.sync.f16 92.3K |
| qu.list.c8 / c16 | 37.7K / 53.0K | ~16K / ~30K | 78.4K / 104.2K |
| qu.list.span.256 | 142.6K | ~50-55K | qu.sync.span 279.9K |
| qu.kick.f8.x64 (build + kick, CPU) | 29.0K | ~3K | |
| qu.wait.f8.x64 (CHISEL after the kick) | 7.0K (~110/op) | | |
| as.lazy.f8.x64 (no replay now) | 55.2K | <= seq | 58.4K |
| cp.lib.4K / cp.chisel.4K / cp.sw.4K | 4,443 / 7,325 / 7,354 | sw = the smaller | |
| stniccc fps | **21.1** | 55-60 | 41.1 |
| fuji / tsl / gen4_3615 fps | 60.4 / 60.2 / 60.4 | 60 | unchanged |

### Diagnosis
1. **stniccc's lists ran on the CPU, not on CHISEL (the regression, fixed in the WIP commit).**
   `cycles/bblit.c` hands an op to CHISEL only when the BLOCK's D_BASE >= OFF_VRAM, else to the
   machine's software blitter (wasm2c'd, CPU stores). The ZigOS queue never writes the block (the
   destination is set in the list), so stniccc's block D_BASE stayed 0 and every QUEUE ran in software
   on ZIGGY. The bench passed because its prep leaves a VRAM D_BASE in the block. Fix: a QUEUE goes to
   CHISEL whatever the block holds (`chisel_takes`); to keep that safe, a queued op whose own D_BASE is
   below OFF_VRAM is refused (cost 0) by BOTH the machine (blitter_queue.zig) and the RTL (zm_blit_q.v:
   SET skips it), since CHISEL's writes there would bypass the compositor's register/palette snoop.
   test_blit_path has a case and a break test for the routing (a QUEUE with a low block D_BASE must not
   reach __real); test_rtl_blitter a `queued_op_below_vram_runs` mutant (the queue script now draws
   some ops below OFF_VRAM). **The RTL change needs a new bitstream** (not built: no Vivado tonight).
   Without it, the refusal is missing on silicon but stniccc never queues below OFF_VRAM, so the new
   firmware on the e237ff42 bitstream would already show the stniccc fix.
2. **The CPU side was instruction-bound, not store-bound.** qu.kick.f8.x64 = ~450 cycles an op. The bench's
   C helpers did ~250 instructions an op (5 non-inlined calls comparing a shadow) plus two variable divides
   (tile_xy, ~80 cycles, also in the sync rows: qu.sync.f16 1,442/op vs ~1,170 expected). The ring stores
   are ordinary posted DDR stores (the region is in the linear window, not IO). Fixes in the WIP commit:
   no compares (a posted store is cheaper than the compare that saves it), a fill = header + 3 words
   stored as given (`List.whole3`, ~4 stores), only set()/op() words carried to the next list; the bench
   mirrors it (q_room/q_fill, no divides). Expected qu.kick.f8.x64 ~3-5K, qu.list.f8.x64 ~10-15K.
3. **D$ sweeps:** a list kicked right behind another (a full half) now only waits; the whole-D$ sweep is
   deferred to the flush/any other sync (by the queue's contract the cart reads none of its pixels before
   the flush). stniccc per frame (browser count): 17-21 kicks, 1-2 flushes, ~3.8-5.2K ring words, ~1014
   descriptors; so ~20 sweeps a frame become 1-2.
4. **chisel_copy:** COPY_MIN 4096 -> 8192 (cp.lib.4K 4,443 < cp.chisel.4K 7,325); rows cp.lib.8K and
   cp.sw.16K added to settle it on the board.

### State of the WIP commit
- Tests passing: test_rtl_blitter (14, including the queue script with low-D ops), test_chisel_async (13
  cases; ZM_RTL_BREAK 10 mutants caught, 2 new: list-after-list sweeps, any lazy op defers),
  test_blit_path + its 2 break tests, test_native_bench, blit_list_test.zig, blitter_queue_check.mjs
  (+ the below-OFF_VRAM refusal). stniccc scene_hash: IDENTICAL to the pre-queue cart, every frame,
  2400 frames (84c2f7961a191a7b).
- Not done tonight: the RTL break run for the queue mutants was started (see logs/), the --only stniccc
  gate was not re-run after these changes, no restage, no Vivado.

### Next steps
1. `flock build.lock ./build.sh --only stniccc`; re-run `ZM_RTL_BREAK=1 test_rtl_blitter.py -k broken`.
2. Vivado (zm_blit_q.v changed: one compare), restage bit + system.rv32 + stniccc + the FAT bench disk.
3. Board: stniccc fps, qu.kick.f8.x64 (expect ~3-5K), qu.list.*, cp.lib.8K vs cp.sw.8K.
4. A golden scene_hash for stniccc in the gate (its harness hashes nothing; it missed a wrong-pixel bug).
