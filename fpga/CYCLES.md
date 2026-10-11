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
| skystrike | ok | 120 | 2.63 | 2.01 | 89.32 | 44.87 | 2.06 | 1.92 | 10.07 | 0.00 | 0% | 120 | 5359 | 120 | 120 | 115 | 261 |
| stniccc | ok | 120 | 0.00 | 0.00 | 0.00 | 0.00 | - | 0.00 | 7.25 | 0.00 | 0% | 0 | 0 | 0 | 0 | 0 | 0 |
| tsl_hybridglenz | ok | 120 | 0.16 | 0.16 | 0.16 | 0.33 | - | 0.12 | 10.06 | 27.31 | 28% | 10 | 10 | 8 | 7 | 5 | 22 |
| tutorial | ok | 120 | 0.60 | 0.60 | 0.60 | 0.60 | 0.73 | 0.43 | 7.29 | 0.00 | 0% | 36 | 36 | 36 | 36 | 26 | 96 |
| ulm_dsots | ok | 120 | 1.69 | 1.69 | 1.69 | 1.69 | 2.38 | 1.62 | 10.05 | 0.00 | 1% | 101 | 101 | 101 | 100 | 97 | 210 |
| union_beatdis | ok | 120 | 0.95 | 1.54 | 2.04 | 0.55 | 2.09 | 0.92 | 7.25 | 0.00 | 0% | 93 | 122 | 93 | 93 | 55 | 238 |
<!-- cycles-table:end -->

## Verdict

*From the 9-cart sample (every run's hashes equal scene_hash.mjs's and the
native host's). stniccc is blind: without its disk stream (`diskReadBlock` is a
no-op in scene_hash.mjs and in both hosts) its cart does almost nothing, so its
row is not evidence. Since 2026-10-11 both hosts take `--disk` and the board
firmware serves the disk from DDR (docs/FPGA_GLASS.md, "The disk in DDR"); this
cycles sim still runs without one.*

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

## Memory path (plan step 0b-iii)

*The caveat of* Sim fidelity *turned into measurements: the board's DDR path is
put back on the main-RAM bus of the same Verilator model, and the remedies are
measured on it. Re-run with `uv run python tools/mempath_run.py memory caches`
(custom cores: `ZM_VEXGEN=1 tools/setup.sh`, then `vexgen/gen.sh`, see below);
`tools/mempath_report.py` rewrites the two tables between their markers.*

### Method

- **A timing model on the main-RAM path** (`soc/zm_memtiming.py`). It sits
  between the SoC interconnect and the one-cycle SRAM and only withholds the
  strobe; data still goes to and from the SRAM, so every run's hashes are
  checked exactly as above (scene_hash.mjs and the native host). Its parameters
  are read at time 0 from `zm_memcfg.init` in the run directory
  (`rtl/sim/zm_memcfg.v`), so one Verilated model runs every memory
  configuration. With every parameter at 0 it is the old sim: tutorial
  (`aligned`, 120 frames) gives the same counters on every frame and the same
  hashes as the run in the table above. `tests/test_memtiming.py` checks each
  parameter in Migen's simulator.
- **What it models.** A read access (one word, or a 32-byte cache-line burst)
  waits `rd_lat` before its first word; the other words come at the sim's own
  rate. A store either waits `wr_lat` (the bridge waits for the AXI write
  response) or goes into a **store buffer** of `sb_depth` entries that is
  acknowledged at once and drains one entry every `sb_drain` cycles; with
  **write combining** the stores to the newest entry's line merge into it, and
  the entry closes on a store to another line or after 16 idle cycles. Reads
  overtake buffered stores (a bridge that compares addresses; `hp_wc_rdwait`
  is the bridge that does not). The **ACP** variant adds a tag-only model of
  the PS's 512 KiB L2 (direct-mapped here, 8-way on the chip, so pessimistic):
  a read that hits costs the L2 latency instead.
- **Every latency is EXTRA** over the sim's own cost, which is 2 cycles a word
  (LiteX's SRAM without burst support), so a line refill is 16 + `rd_lat`
  cycles. (The 9 cycles quoted in *Sim fidelity* were wrong: it was 16.) That
  base is already slower than the board's 64-bit HP port, which delivers a word
  per cycle once the first arrives, so the figures below are conservative by
  about 8 cycles a refill.
- **The build is `aligned`** (no bounds checks, one `lw`/`sw` per wasm access,
  misalignment trapped and emulated): the two wins already identified, now the
  default. `nobounds` is measured on three configurations for comparison.
- **Carts and frames.** The four that set the clock among the carts that fit:
  union_beatdis (120 frames: its heavy effects come after frame 30), skystrike
  (48: its steady phase starts at 30), ulm_dsots and tutorial (30: flat).
  polkadots (12 frames) only for the I-cache. MHz = p95 cart frame x 60, as above.
- **Other cores** (`vexgen/`): LiteX's `standard` regenerated from the pinned
  `third_party/VexRiscv` (SpinalHDL 1.13) with the cache size and way count as
  parameters (`vexgen/GenZm.scala`, the plugins of `standard` only; same
  ports). `I4D4` is that regeneration of `standard` itself, a check of the
  generator. JDK 11 and sbt are fetched into `fpga/.tools/` by
  `ZM_VEXGEN=1 tools/setup.sh` (pinned, checksummed); the box's JDK 21 is too
  new for VexRiscv's sbt. `tools/util.py` synthesises every generated core
  (`vex_<name>`), which gives the LUT/BRAM columns.

### The latencies, and where they come from

The cart CPU and the HP port both at 150 MHz (6.7 ns a cycle).

| path | first word | derivation |
|---|---|---|
| HP, unloaded (`hp`) | +24 (~170 ns) | DDR3-1066 behind the PS DDRC: a Cortex-A9 load that misses to DDR takes ~88 CPU cycles, 110 ns ([JBLopen, Zynq-7000 bare-metal benchmarks](https://www.jblopen.com/zynq-benchmarks/)); plus the AFI FIFOs, the PL/PS clock crossing both ways and the bridge, ~40-60 ns. UG585 §22.4.4: the HP ports' "additional logic and arbitration does result in higher minimum latency than other interfaces". |
| HP, loaded (`hp_load`) | +62 (~410 ns) | UG1145 (SDK System Performance Analysis) ch. 8, ZC702: "the average read latency [...] from the DDR is 40-44 cycles" of the 100 MHz PL clock with four HP masters saturating the DDR, i.e. 400-440 ns. |
| store, blocking (`hp`) | +24 | the AXI write response comes back from the DDRC (UG585 §5.3: "Write commands and data are sent the entire path to the slave [...] and the response is issued by the slave"). |
| store buffer (`hp_sb`) | 0 if not full | 8 entries (an HP port accepts 8-32 write commands, UG585 §5.3.1); one single-beat write drains every 2 cycles (a DDR3 x16 BL8 burst is 7.5 ns). |
| write combining (`hp_wc`) | 0 if not full | 8 line entries, one 32-byte burst every 4 cycles (two BL8 bursts on the board's x16 DDR3). |
| ACP (`acp_wc`) | +20 miss, +10 L2 hit | UG585 §22.4.4: the ACP "has the lowest memory latency to memory of the PL interfaces"; an A9 L2 hit is ~31 ns (JBLopen), plus the PL/PS crossing. Stores as `hp_wc`. |

`hp_free` (stores cost nothing, reads as `hp`) is not a design: it is the bound
that no store policy can beat, a write-back D$ included (see *Write-back*).

These are derived, not measured on the board: the DDRC's real figure depends
on the `ps7_init` timings, refresh, bank conflicts and the other masters (the
video DMA, the ARM). The parameters are run-time, so better numbers from a
board measurement only need `tools/mempath_cfg.py` edited and a re-run.

### Results: the memory path (`standard` core, MHz for 60 fps)

<!-- mempath-memory:begin -->
| cart | build | sram | hp | hp_sb | hp_wc | hp_wc_rdwait | hp_free | hp_load | hp_load_wc | acp_wc |
|---|---|---|---|---|---|---|---|---|---|---|
| union_beatdis | aligned | 55 | 194 | 61 | 61 | 62 | 61 | 462 | 69 | 58 |
| ulm_dsots | aligned | 98 | 248 | 112 | 112 | - | 112 | 585 | 135 | 106 |
| skystrike | aligned | 115 | 325 | 129 | 129 | - | 129 | 775 | 152 | 124 |
| tutorial | aligned | 26 | 98 | 28 | 28 | - | 28 | 236 | 32 | 27 |
| union_beatdis | nobounds | 93 | 340 | - | 128 | - | - | - | - | - |
| ulm_dsots | nobounds | 102 | 270 | - | 115 | - | - | - | - | - |
| skystrike | nobounds | 120 | 346 | - | 137 | - | - | - | - | - |
| tutorial | nobounds | 36 | 145 | - | 44 | - | - | - | - | - |
<!-- mempath-memory:end -->

### Results: the caches (on `hp_wc`)

<!-- mempath-caches:begin -->
| core | LUT | BRAM (36 Kb) | skystrike | polkadots | polkadots I$ refills/frame |
|---|---|---|---|---|---|
| std | 2019 | 5 | 129 | 3333 | 792k |
| I4D4 | 2038 | 5 | 129 | 3333 | 792k |
| I16D4 | 2062 | 8 | 128 | 1627 | 151k |
| I16w2D4 | 2066 | 8.5 | 119 | 1381 | 57k |
| I32w2D4 | 2044 | 12.5 | 118 | 1229 | 1k |
| I16w2D16w2 | 2133 | 11 | 117 | 1349 | 57k |
| I4D16w2 | 2092 | 7.5 | 128 | 3301 | 792k |
<!-- mempath-caches:end -->

*All 59 runs' hashes equal scene_hash.mjs's and the native host's. polkadots
on the one-cycle SRAM (`std`, `sram`, same 12 frames) needs 2165 MHz.*

### What the measurements say

1. **Blocking stores are the whole problem, and any store buffer removes it.**
   With the bridge waiting for each AXI write response (`hp`), every cart
   needs 2.5-3.8x its SRAM clock (union_beatdis 55 -> 194 MHz, skystrike 115
   -> 325): the write-through D$ turns 85-250 K stores a frame into 85-250 K
   round trips. An 8-entry posted-write buffer (`hp_sb`) gives **exactly** the
   cycles of `hp_free`, where stores cost nothing: the buffer never fills on
   these carts (union_beatdis's 125 K stores are spread over the frame, at
   most one per few cycles, and an entry leaves every 2). Write combining
   (`hp_wc`) changes no cycle on top of that, and neither does making reads
   wait for the buffer to drain (`hp_wc_rdwait`: 61 -> 62 MHz).
2. **So a write-back D$ is not needed.** `hp_free` is the bound for any store
   policy, and the plain store buffer already reaches it; a write-back D$ could
   only also save the read misses a write-allocate would turn into hits, which
   the bigger-D$ rows below bound at 1-2 %. VexRiscv's D$ is write-through
   only, VexiiRiscv's is write-back, and neither is worth the switch.
3. **What is left is read latency: +6-14 %.** On the HP port with a store
   buffer the four carts need 61, 112, 129 and 28 MHz against 55, 98, 115 and
   26 on the one-cycle RAM. Under a saturated DDR (`hp_load_wc`, 410 ns a
   refill) 69, 135, 152 and 32.
4. **The ACP is a little faster than HP, not decisively** (`acp_wc`: 58, 106,
   124, 27, within 5-8 % of the SRAM). Its L2 is shared with Linux on the ARM
   and its SCU path with the ARM's own traffic, neither of which is modelled.
5. **The I-cache is the cheap win.** A 16 KiB 2-way I$ cuts polkadots's
   refills from 792 K to 57 K lines a frame (3333 -> 1381 MHz on `hp_wc`,
   under its 2165 on the one-cycle RAM with the old I$) and takes skystrike
   from 129 to 119 MHz, below its old SRAM figure. Direct-mapped 16 KiB leaves
   151 K refills (conflicts); 32 KiB 2-way removes them all but buys skystrike
   only 1 MHz more for 4 more BRAMs. A bigger D$ moves almost nothing (D$ 16
   KiB 2-way: skystrike 129 -> 128 with the small I$, 119 -> 117 with the big).
   The four clock-setting carts refill only 1-5 K lines a frame, so their
   I$ gains are small; only skystrike was re-run on every core.
6. **`aligned` matters more on DDR, not less.** `nobounds` (memcpy-based wasm
   accesses: byte stores) on `hp_wc` needs 128 MHz for union_beatdis against
   61 for `aligned`, and 44 against 28 for tutorial; with blocking stores
   (`hp`) it needs 340.
7. **`I4D4` gives the same cycles as LiteX's `standard`** on both carts it ran:
   the generator rebuilds the same core, so the other rows differ from
   `standard` by their caches only.

### Cost of each remedy (Yosys `synth_xilinx`, xc7)

| remedy | LUT | BRAM (RAMB36 eq.) | source |
|---|---|---|---|
| core `standard` (I$ 4 KiB, D$ 4 KiB) | 2,019 | 5 | `tools/util.py vexriscv_std` |
| core I$ 16 KiB 2-way, D$ 4 KiB | 2,066 (+47) | 8.5 (+3.5) | `tools/util.py vex_I16w2D4` |
| core I$ 32 KiB 2-way, D$ 4 KiB | 2,044 | 12.5 | `vex_I32w2D4` |
| core I$ 16 KiB 2-way, D$ 16 KiB 2-way | 2,133 | 11 | `vex_I16w2D16w2` |
| store buffer, 8 x (addr, word, byte mask) | ~50 (11 RAM32M + control) | 0 | one-off Yosys run of migen's `SyncFIFO(66, 8)` |
| write combining, 8 x 32-byte lines | ~220 (53 RAM32M) + ~100 merge logic, ~330 FF | 0 | `SyncFIFO(315, 8)`, merge logic estimated |

The 7010 has 17,600 LUTs and 60 RAMB36. The Wishbone-to-AXI bridge itself is
needed by every option and is in the plan's "AXI interconnect, HP masters"
line already.

### Recommendation

- **Core:** VexRiscv `standard` with a **16 KiB 2-way I$ and the 4 KiB
  direct-mapped D$**, write-through: `vexgen/gen.sh I16w2D4:16384:2:4096:1`.
  +47 LUT and +3.5 BRAM over `standard`. No FPU (unchanged), no write-back D$.
- **Store path:** an **8-entry posted-write buffer** in the bridge to the HP
  port, acknowledging a store at once and draining one single-beat AXI write at
  a time, reads overtaking it with an address check (or not: 1 MHz). ~50 LUTs.
  Write combining buys no cycle here; add it only if the DDR's write
  bandwidth gets tight next to the video DMA (it halves the write
  transactions).
- **Port:** an **AXI HP port** (HP0, 64-bit), the cart's whole RAM in DDR. The
  ACP would gain 4-8 % at the cost of sharing the ARM's L2 and SCU; keep it as
  the fallback if board measurements put the HP latency well above the
  estimate.
- **Builds:** `aligned` (no bounds checks, one `lw`/`sw` per wasm access,
  misalignment trapped) is the board's build.
- **Clock: 150 MHz still holds** (in this simulation; under openXC7 the board
  closes ~100 MHz, see *Branch prediction and the clock* below). With the recommended core and path the
  worst of the four carts that set the clock is skystrike at 119 MHz on the
  unloaded estimate (26 % margin) and 152 MHz on the standard core under a
  saturated DDR; the big I$ takes 10 MHz off skystrike at the nominal
  latency, so the loaded case should land near 140. union_beatdis 61 MHz,
  ulm_dsots 112 (standard core), tutorial 28. polkadots and replicants_emlyn
  stay out of reach (the *Verdict*: their `f64` code has to change).

### Caveats

- **The latencies are derived, not measured** (the sources above). The first
  board bring-up should time a refill through the HP port and a posted write's
  drain, then re-run with those numbers in `tools/mempath_cfg.py`.
- **Not modelled:** contention between the store buffer's drain and the reads
  (both on one HP port and one DDR), the video DMA's and the ARM's DDR traffic
  except as the `hp_load` latency, DDR refresh and bank conflicts as anything
  but an average, and the ARM's use of the L2 in `acp_wc`.
- **The sim's own 2 cycles a word** make every refill about 8 cycles slower
  than a 64-bit HP port would, so the figures are slightly pessimistic.
- **Everything is in DDR**, code included. The ROM in BRAM (the plan's "ROM
  chip") would only take fetches off the DDR, so it can only help.
- **Coverage:** four carts on every memory configuration, two on every cache
  geometry; union_beatdis 120 frames, skystrike 48, ulm_dsots and tutorial 30,
  polkadots 12.

## Branch prediction and the clock (timing pass 2)

*Why this section exists: under openXC7 the sealed core's critical path was its
static branch predictor (fpga/TIMING_FABLE.md: 82 MHz with it, 99.5 without, one
seed each), so the predictor was put on trial: what it costs in cycles, what it
buys in fmax, and which wins per frame. Re-run with
`uv run python tools/mempath_run.py prediction` (cores from
`vexgen/gen.sh ...:nopred|dynpred`); the table between the markers is
`tools/mempath_report.py`'s.*

**Cycles.** The recommended core (16 KiB 2-way I$, 4 KiB D$) with static
prediction, a dynamic target predictor (`dynpred`: VexRiscv's
`DYNAMIC_TARGET`, a BTB in the fetch stage), none (`nopred`), and none plus
`relaxpc` (one more fetch stage), on the board's memory path (`hp_wc`,
`aligned`), MHz for 60 fps on the p95 frame. Unsealed cores: the seal costs no
cycle (rtl/seal/README.md). Every run's hashes equal scene_hash.mjs's and the
native host's.

<!-- mempath-prediction:begin -->
| core | union_beatdis | ulm_dsots | skystrike | tutorial | cycles vs static |
|---|---|---|---|---|---|
| I16w2D4 | 52 | 98 | 119 | 26 | +0.0 % / +0.0 % / +0.0 % / +0.0 % |
| I16w2D4Dyn | 47 | 89 | 107 | 22 | -11.2 % / -9.1 % / -9.8 % / -14.1 % |
| I16w2D4Nopred | 62 | 114 | 141 | 32 | +18.8 % / +16.5 % / +18.8 % / +24.5 % |
| I16w2D4RpcNopred | 68 | 123 | 153 | 36 | +29.4 % / +25.3 % / +28.5 % / +37.5 % |
<!-- mempath-prediction:end -->

**fmax** (nextpnr's figure for `sys`, the glass SoC with the DDR-framebuffer
video and the compositor on its own clock, openXC7 flow of `soc/openxc7.py`,
same RTL, seeds 1-6; fpga/README.md "Timing under openXC7"):

| core (sealed) | seeds | sys fmax min / median / max | seeds at >= 100 MHz |
|---|---|---|---|
| static (`I16w2D4Seal`, the board's) | 1-12 | 76.1 / 92.9 / 102.0 MHz | 3 (seeds 1, 8, 10) |
| static, seeds 1-6 only | 1-6 | 82.8 / 90.7 / 102.0 MHz | 1 |
| none (`I16w2D4SealNopred`) | 1-6 | 90.7 / 99.9 / 108.9 MHz | 3 (seeds 4, 5, 6) |
| dynamic target (`I16w2D4SealDyn`) | 1, 2 | does not route: overuse climbs past iteration 50 (killed at 25 min, three times) | - |

Without prediction the sys clock gains about 10 % at the median and 7 % at
the best seed. Pass 1's 82 -> 99.5 MHz was one seed of each core on an earlier
netlist: the predictor's cone is no longer what limits `sys`. The critical paths
are VexRiscv's execute stage (operand mux -> adder carry -> bypass, 8 ns of 11
routing) and the I$ tag RAM -> decode -> register-file address, and they move
with the seed.

**Verdict.**

- **No prediction loses.** It costs 16.5-24.5 % more cycles a frame for about
  8-10 % more clock: per frame it is 6-15 % slower than the static core
  (skystrike: 141 MHz needed against 119; at the median seed 99.9 / 141 = 71 %
  of real time against 90.7 / 119 = 76 %). The board keeps **static
  prediction** (`soc/zm_z7.py` `BOARD_CORE`, `make -C fpga vexgen-board`);
  `I16w2D4SealNopred` is built alongside for `--cpu-netlist`.
- **A dynamic target predictor would win on cycles** (9-14 % fewer than
  static: skystrike 107 MHz, ulm_dsots 89) but does not route under openXC7
  yet. It is the first thing to try in pass 3 (routing congestion, not timing).
- **What each cart needs on the board core** (static, `hp_wc`, `aligned`, p95
  frame): union_beatdis 52 MHz, ulm_dsots 98, skystrike 119, tutorial 26.
  The pinned build closes **sys at 100.6 MHz** (seed 8, fpga/README.md
  "Timing under openXC7"): union_beatdis and tutorial fit with room, ulm_dsots
  fits with 3 %, **skystrike does not** (84 % of real time, ~50 fps on its
  sustained load). So ~100 MHz suffices for three of the four clock-setting
  carts, not all; the 150 MHz plan above stays out of reach under openXC7.
- **Not in these numbers:** the sequencer's own time (fpga/rtl/video/README.md
  "Integration": issuing passes and waiting for them, ~0.65 M sys cycles a frame
  at 160 MHz in the video sim), which the compositor's own, faster clock shortens
  but does not remove.

## f32 FPU

*Matt approved an f32 FPU as "good enough for an oldskool machine"; this is its
bill. Re-run with `vexgen/gen.sh I16w2D4SealDynT8Fpu:16384:2:4096:1:seal,dynpred,h8,fpu`
and `uv run python tools/mempath_run.py fpu` (the table is `tools/mempath_report.py`'s).*

**The core.** VexRiscv's `FpuPlugin`, single precision only (`FpuParameter(withDouble =
false, mulWidthA = 24, mulWidthB = 17)`: a mantissa product is two 25x18 DSP48E1, the
register file is synchronous), on the pass-3 board core (sealed, 16 KiB 2-way I$, 4 KiB D$,
`DYNAMIC_TARGET` with a 256-entry BTB: `vexgen` flags `dynpred,h8,fpu`). The baseline is
the same core without `fpu`. Firmware: `cycles.mk` variant `alignedf` = `aligned` built
`-march=rv32imf -mabi=ilp32f` (picolibc has the multilib), `-ffp-contract=off` kept, and
`trap_install()` sets `mstatus.FS` (an F instruction is illegal while FS is Off).

**Cost** (Yosys `synth_xilinx`, `tools/util.py`, sealed cores; the board SoC is the
whole-design `synth_xilinx` of `soc.zigmachine_soc --target z7`):

| | LUT | FF | BRAM (18 Kb) | DSP | LUTRAM |
|---|---|---|---|---|---|
| core, no FPU (`I16w2D4SealDynT8`) | 2,137 | 1,534 | 14 | 4 | 0 |
| core + f32 FPU | 4,485 | 3,434 | 17 | 6 | 5 |
| **FPU increment** | **+2,348 (13 % of the 7010)** | +1,900 | +3 | +2 | +5 |
| board SoC, no FPU | 9.7 K (55 %) | 8.5 K | 36 | 17 | |
| board SoC + FPU | 13.6 K (77 %) | 11.8 K | 39 | 19 | |

**Cycles** (cart CPU, p95 frame, `hp_wc` memory path; MHz for 60 fps; soft = libgcc
soft-float on the non-FPU core, FPU = hard-float on the FPU core). Every run's hashes
equal scene_hash.mjs's and the native host's (16/16 `ok`), so `-ffp-contract=off`, the
FPU's rounding, NaN and subnormal handling change no result in these 8 carts.

<!-- mempath-fpu:begin -->
| cart | soft Mc | FPU Mc | soft MHz | FPU MHz | cycles |
|---|---|---|---|---|---|
| union_beatdis | 0.78 | 0.78 | 47 | 47 | -0 % |
| ulm_dsots | 1.49 | 1.49 | 89 | 89 | -0 % |
| skystrike | 1.79 | 1.79 | 107 | 107 | +0 % |
| tutorial | 0.37 | 0.37 | 22 | 22 | +0 % |
| blitter | 0.10 | 0.06 | 6 | 4 | -39 % |
| tsl_hybridglenz | 0.09 | 0.07 | 5 | 4 | -19 % |
| polkadots | 20.95 | 22.18 | 1257 | 1331 | +6 % |
| replicants_emlyn | 4.99 | 5.25 | 300 | 315 | +5 % |
<!-- mempath-fpu:end -->

**Verdict.**

- **The FPU saves nothing that matters.** The four carts that set the clock
  (union_beatdis 47, ulm_dsots 89, skystrike 107, tutorial 22 MHz) are bit for bit as fast
  without it: they have no f32 work. blitter and tsl_hybridglenz gain 19-39 % of a
  load that is 4-6 MHz anyway. polkadots and replicants_emlyn compute in **f64**, which
  an f32 FPU does not run, and they get 5-6 % *slower* (cause not chased: the
  f64 stays in libgcc, now built for the hard-float ABI). Their need
  (1.3 GHz, 300 MHz) stays out of reach: the fix is in the scenes (f32 or fixed point).
- **LUTs.** +2,348 LUT (+1,900 FF) for the core, the board SoC from 55 % to 77 % of the
  7010's LUTs, with the blitter and the audio still to come (~10.6 K LUT used before this
  one). It still fits on paper; it leaves about 4 K LUT for the blitter + audio.
- **fmax.** the non-FPU board SoC (sealed DynT8 core, seed 5, current tree) routes
  and gives **sys 91.7 MHz** (comp 112.3). The FPU SoC (13.6 K LUT, 77 %) **did not place**:
  nextpnr-xilinx's HeAP placer stalls after its 5th iteration (`congestion-spread`
  loop, 100 % CPU, no output) and was killed at the 1,500 s cap and again at 3,600 s,
  seed 5, the board flow of `soc/openxc7.py`. So there is no FPU fmax; the flow
  as pinned cannot build this core, and finding out why (density? more seeds,
  `--placer-heap-congestion-weight`, no `-spread`) is the first job if the FPU is
  ever wanted.
- **Call:** the oldskool-machine argument is real (carts written in f32 become possible),
  but no cart of the shelf runs faster for it and it costs 13 % of the chip and
  fmax margin. Keep it as an opt-in core (`vexgen ... fpu`), not the board core, until a
  cart is written in f32. If it is wanted, `-mno-fdiv` plus `withDiv/withSqrt = false`
  would trim it further (not measured).

## The two float carts, rewritten (2026-10-10)

*The* Verdict *above said the fix for polkadots and replicants_emlyn is in the
scenes. It is done: both default carts now run integers (fixtrig sine tables,
Q16.16, spans), and the CODEF algorithms they replaced are kept, in f32, as
the twin carts `polkadots_f32` and `replicants_emlyn_f32` for the f32 FPU.*

**Method.** The cycles sim of this file's first table (`standard` core, 4 KiB
I$, one-cycle SRAM), build `aligned` for the cart figure and `float` for the
soft-float share; cart cycles per frame averaged after frame 5. Run by hand:
`make cycles-fw CART=<tag> VARIANT=aligned` then `tools/cycles_sim.sh`
(8-14 frames each, so the hashes were not compared with scene_hash.mjs: the
harnesses compare the pictures instead, see below). ZIG mode (Space) is
measured with `-DZM_FIRE_AT=1` in `V_aligned`: `cycles/main.c` then calls
`input(5)` before frame 1; the bars reach their widest ramp by frame 8.

| cart | before (f64) | after | MHz for 60 fps | soft-float |
|---|---|---|---|---|
| replicants_emlyn, ORIGINAL | 7.74 Mc | **0.20 Mc** | 464 -> **12** | 42 % -> 0 |
| replicants_emlyn, ZIG (Space) | 301 Mc at frame 8, still rising | **1.55 Mc** (p95 1.59) | > 18,000 -> **96** | |
| polkadots | 35.65 Mc | **1.32 Mc** | 2139 -> **80** | 49 % -> 0 |
| replicants_emlyn_f32, ORIGINAL | | 2.17 Mc | 130 | 47 % |
| replicants_emlyn_f32, ZIG | | 30 Mc on frame 1, rising | | |
| polkadots_f32 | | 17.04 Mc | 1023 | 42 % |

Where the cycles went (removing one part at a time, same sim):
- **emlyn**: after the integer rewrite the ORIGINAL frame was 3.3 Mc, of which
  the CPU logo blit (112,000 keyed pixels) was 1.8 and the ramp copy under it
  (112 KB) 0.9. Both now go to the blitter: the logo cookie-cut from cart RAM,
  the ramp written once and doubled down the plane in nine copies. In ZIG mode
  the raster fill (the bars painted once into a 1/16 px strip along the bars'
  axis, each line a walk along it) and the HBL's per-line palette writes (up
  to 149 entries x 280 lines, 0.64 Mc: the price of real rasters) are the rest.
- **polkadots**: the fill had been 0.95 Mc of 1.65 because libgcc's 64-bit
  divide (one per edge, two per vertex) costs about a thousand cycles on rv32;
  every divide is now one 32-bit hardware divide.

**The look.** Both default carts are compared with the old f64 builds and
with their f32 twins (`apps/*_headless.mjs` now checks fixed against f32):
emlyn ORIGINAL differs from the f64 build in at most 400 of 112,000 pixels a
frame (one band edge one line over), ZIG in at most 391; polkadots in 5 of
13,174 lit cells over 60 frames, each one dot size apart.

**The f32 FPU.** The f32 twins are what an F-only FPU can speed up: replacing
their soft-float by the FPU costs of *FPU estimate* saves **46 %** of
replicants_emlyn_f32's frame and **40 %** of polkadots_f32's (float-build
basis), against 1 % for the old f64 carts. A few f64 calls remain inside
compiler-rt's `sinf`/`cosf` (23-30 a frame).

**Board estimate** (100 MHz board clock, +15 % for the DDR path's read
latency, *Memory path*): emlyn ORIGINAL 0.23 Mc of a 1.67 Mc frame, 60 fps; ZIG
1.8 Mc, about 55 fps at the widest ramp and 60 below it; polkadots 1.5 Mc,
60 fps (it ran at 2 fps). Not counted: the blitter's own time for the logo and
the ramp (RTL, 224,000 pixels a frame in the worst case).
