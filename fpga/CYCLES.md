# Cycles per frame on the cart CPU (plan step 0b-ii)

*Generated table plus hand-written method and verdict. Re-run with
`make -C fpga cycles CARTS="..."`; `tools/cycles_report.py` rewrites the table
between the markers. Details per run are in `build/cycles/report.txt`.*

## Method

- **The CPU is the real one.** The SoC of `soc/zigmachine_soc.py`, VexRiscv
  `standard` (rv32im, 5 stages, 4 KiB direct-mapped I$ and D$, write-through D$,
  single-cycle multiply, iterative divide), simulated cycle by cycle in
  Verilator (`soc/cycles_sim.py`). Only the memory differs from the board: 32
  MiB of on-chip SRAM that answers in one cycle (see *Sim fidelity*).
- **The program is the step 0b-i native host,** built bare-metal for rv32im with
  GCC 13 and picolibc: machine-video + rom + one cart, translated by wasm2c,
  driven exactly like `apps/scene_hash.mjs` (`cycles/README.md`). The stock
  wasm2c runtime compiles unchanged through a three-header shim (`cycles/shim/`).
- **Correctness first.** Every run prints the scene_hash JSON for its sampled
  frames, and its column `hashes` says `ok` only if that JSON equals BOTH
  `apps/scene_hash.mjs`'s and the native host's for the same frames.
- **The split.** A hardware cycle counter is read at every boundary between
  owners (`cycles/prof.c`): **cart** = `cart.frame()` + every HBL handler
  (`hblDispatch`, called from inside `hwRenderPlane`) + the rom code they call;
  **machine render** = `hwClear` + `hwRenderPlane` minus the handlers; **blitter**
  = `hwBlit` from anywhere. The machine and the blitter become RTL on the board,
  so the **cart** columns are the CPU's load. The probe's own cost is calibrated
  and subtracted per span.
- **Frames.** The sample: 120 frames per run (2 s of a 60 Hz screen), hashed
  at frame 120. The rest of the shelf: 60 frames, `nobounds` and `float` only.
  Frames 1-5 are reported apart (`first max`): a screen builds its tables
  there, once. `avg`, `p95` and `max` are over the frames after that. `p95` is
  the sustained load; `max` also catches one-off frames (skystrike's frame 29
  costs 89 Mc, a phase change, against 2 Mc steady).
- **Builds.** `nobounds` (no per-access bounds check: on the board the bus
  window seals the cart) is the reference. `stock` keeps wasm2c's bounds
  checks. `aligned` also lets the compiler use one `lw`/`sw` per wasm access
  instead of the 9 instructions GCC must emit for wasm2c's `memcpy` on a core
  that traps on misaligned words; the rare misaligned access is trapped and
  emulated, and counted.
- **MHz** = cart cycles per frame x 60 / 10^6 (`p95` frame, and `max` frame):
  the clock at which that frame still makes 60 fps. `MHz soft+DDR` adds an
  ASSUMED board memory penalty (see *Sim fidelity*).
- **Toolchain.** GCC 13.2 `-O2 -march=rv32im -mabi=ilp32 -ffp-contract=off`,
  picolibc; soft-float is libgcc's (same entry points as compiler-rt). The sim
  runs about 0.7 M cycles per second, so a 120-frame run takes 20-90 minutes.

### FPU estimate

The `float` build wraps every soft-float routine (libgcc `__addsf3`... and libm
`sqrtf`, `floorf`...) with `ld --wrap`, counts each call per class and times it
with the cycle counter (`cycles/fcount.c`). `float share` = soft-float cycles /
cart cycles. The FPU estimate replaces, frame by frame, the measured soft-float
cycles of each class an FPU implements by `calls x cost`, with these costs (a
dependent chain on the VexRiscv FPU: add/mul pipelined, divide radix 4, sqrt
radix 2, per `third_party/VexRiscv/README.md`):

| class | F (f32) | D (f64, `F+D` column) |
|---|---|---|
| add/sub, mul | 5 | 6, 7 |
| div | 18 | 32 |
| sqrt | 30 | 60 |
| compare, convert i32 | 2, 3 | 2, 3 |
| floor/ceil/trunc/nearbyint (libm with F) | 12 | 14 |
| f32 <-> f64 | soft | 3 |
| i64 <-> float | soft (rv32 has no such instruction) | soft |

The estimate is conservative: with a hard-float ABI the call, the argument
moves and the NaN-boxing checks also go, and the routines stop competing for
the I-cache.

## Results

The sample (union_beatdis, blitter, tsl_hybridglenz, polkadots, stniccc,
skystrike, ulm_dsots, tutorial, replicants_emlyn) is complete in every
variant; rows for the rest of the shelf appear as their runs land
(`uv run python tools/cycles_report.py` re-reads `build/cycles/uart/`).

<!-- cycles-table:begin -->
| cart | hashes | frames | cart avg Mc | cart p95 Mc | cart max Mc | first max Mc | stock p95 Mc | aligned p95 Mc | machine render avg Mc | blitter avg Mc | float share | MHz soft p95 | MHz soft max | MHz FPU p95 | MHz FPU F+D p95 | MHz FPU+aligned p95 | MHz soft+DDR p95 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| blitter | ok | 120 | 0.14 | 0.14 | 0.14 | 0.14 | - | 0.13 | 7.25 | 7.03 | 78% | 9 | 9 | 4 | 2 | 4 | 18 |
| polkadots | ok | 120 | 34.24 | 37.70 | 38.47 | 37.98 | - | 36.16 | 7.25 | 2.61 | 83% | 2262 | 2308 | 2236 | 449 | 2144 | 4527 |
| replicants_emlyn | ok | 120 | 8.37 | 9.17 | 9.22 | 8.83 | - | 8.27 | 10.04 | 0.00 | 65% | 550 | 553 | 544 | 209 | 490 | 1062 |
| skystrike | ok | 120 | 2.63 | 2.01 | 89.32 | 44.87 | - | 1.92 | 10.07 | 0.00 | 0% | 120 | 5359 | 120 | 120 | 115 | 261 |
| stniccc | ok | 120 | 0.00 | 0.00 | 0.00 | 0.00 | - | 0.00 | 7.25 | 0.00 | 0% | 0 | 0 | 0 | 0 | 0 | 0 |
| tsl_hybridglenz | ok | 120 | 0.16 | 0.16 | 0.16 | 0.33 | - | 0.12 | 10.06 | 27.31 | 28% | 10 | 10 | 8 | 7 | 5 | 22 |
| tutorial | ok | 120 | 0.60 | 0.60 | 0.60 | 0.60 | - | 0.43 | 7.29 | 0.00 | 0% | 36 | 36 | 36 | 36 | 26 | 96 |
| ulm_dsots | ok | 120 | 1.69 | 1.69 | 1.69 | 1.69 | - | 1.62 | 10.05 | 0.00 | 1% | 101 | 101 | 101 | 100 | 97 | 210 |
| union_beatdis | ok | 120 | 0.95 | 1.54 | 2.04 | 0.55 | 2.09 | 0.92 | 7.25 | 0.00 | 0% | 93 | 122 | 93 | 93 | 55 | 238 |
<!-- cycles-table:end -->

## Verdict

*From the 9-cart sample (every run's hashes equal scene_hash.mjs's and the
native host's). stniccc is blind: without its disk stream (`diskReadBlock` is a
no-op in scene_hash.mjs and in both hosts) its cart does almost nothing, so its
row is not evidence.*

**Clock: plan for 150 MHz, not 100.** Six of the eight measurable carts fit a
VexRiscv `standard` at a realistic clock: blitter 9, tsl_hybridglenz 10,
tutorial 36, union_beatdis 93 (122 on its worst frame), ulm_dsots 101 and
skystrike 120 MHz (p95, `nobounds`, soft-float). 100 MHz misses two of them
on the sustained load (ulm_dsots, skystrike) and union_beatdis on its worst
frame. 150 MHz covers all six with about 25 % margin, but only in this zero-wait
sim; see *Sim fidelity*, which can eat that margin on DDR.

**FPU: no.** An `f32` FPU (3,000-5,000 LUTs on the 7010) buys almost nothing:
the float share of the six carts that fit is 0-28 % apart from blitter (78 %, of
a cart that needs 9 MHz), and the F estimate moves nobody across a clock line
(blitter 9 -> 4 MHz, tsl_hybridglenz 10 -> 8). The two float-heavy carts compute
in **`f64`**, so an F-only FPU leaves them unchanged (replicants_emlyn 550 ->
544 MHz, polkadots 2262 -> 2236). Even F+D (more LUTs again) only reaches 209
and 449 MHz. Their `f64` is in the scenes' own code, not a shared lib:
`apps/zig/scenes/polkadots/shade.zig`, `torus.zig`, `replicants_emlyn/*.zig`
declare `f64` constants and math (CODEF ports keep JavaScript's doubles), plus
three helpers that both carts share (likely `std.math` trig on `f64`). The fix is
in those scenes (fixed point, or `f32` plus fewer divides), not in the fabric.
Even float-free they are heavy: their non-float remainder is about 3.2 Mc
(emlyn) and 6 Mc (polkadots) per frame, so both need real optimisation work
before any 7010 plan can run them.

**Cheaper levers than an FPU, in order:**
1. **Trust alignment in the translation (`aligned`).** wasm2c's `memcpy` access
   costs 9 instructions per load on a core that traps on misaligned words. Using
   one `lw`/`sw` and emulating the rare misaligned access in the trap handler
   cuts the cart's p95 by 4-40 % (union_beatdis 1.54 -> 0.92 Mc, tutorial 0.60
   -> 0.43) and the misaligned accesses are rare (0 to about 150 per frame). With
   it, 100 MHz covers five of the six on p95 (skystrike needs 115).
2. **Drop the bounds checks.** The bus window seals the cart, and `stock` costs
   +36 % on union_beatdis (more carts are queued).
3. **A bigger I-cache.** The `standard` core's 4 KiB direct-mapped I$ thrashes:
   polkadots refills about 770 K lines a frame, and union_beatdis jumps from 0.55
   to 2 Mc/frame when its later effects no longer fit. A 16 KiB I$ costs a few
   BRAMs. This was not measured: the cores LiteX ships all have 4 KiB caches, and
   generating another needs SpinalHDL on a JDK 8 (the box has only JDK 21).

## Sim fidelity (how optimistic these numbers are)

The CPU is cycle-exact. The memory is not the board's: main RAM is an on-chip
SRAM that answers a wishbone access in one cycle, so a 32-byte cache-line refill
costs about 9 cycles here, and each store (the D$ is **write-through**: every
store is a bus transaction) about 1 wait cycle. On the Z7 the cart CPU reaches
DDR through the PS (AXI HP port), where a miss costs tens of cycles more.

ZMCycles counts that traffic per frame (`build/cycles/report.txt`, `cart bus/frame`),
so the gap can be priced. `MHz soft+DDR` ASSUMES +30 cycles per line refill and
+10 per store (posted writes through an AXI bridge). With that, union_beatdis
goes from 93 to 238 MHz, ulm_dsots from 101 to 210, skystrike from 120 to 261:
**the store stream, not the instructions, would dominate.** union_beatdis issues
about 125 K stores a frame; at 150 MHz a frame is 2.5 M cycles, so 10 cycles a
store is half the budget. The board design therefore matters as much as the
clock: a write buffer or a write-back D$, cart work RAM in BRAM, or a low-latency
DDR path. Until one of those is chosen, read the sim numbers as a lower bound,
optimistic by up to about 2.5x for store-heavy carts.

Also outside the measurement:
- **Audio.** scene_hash.mjs stubs every audio import, and SNDH runs on the
  audio core in the plan, so the cart CPU's figures exclude music.
- **Disk.** Streamed carts (stniccc) do no streaming work here.
- **The machine's own cost.** `machine render` (about 7.3 Mc per plane-frame) and
  `blitter` (up to 27 Mc in tsl_hybridglenz) are measured but irrelevant to the
  CPU: they become RTL. They do show that a soft blitter would never fit.
- **Probe cost.** A span probe costs about 360 cycles. It is calibrated and
  subtracted per span, and only HBL-heavy carts carry many spans (a few hundred
  a frame).
