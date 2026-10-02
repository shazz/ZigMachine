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
- **Clock: 150 MHz still holds.** With the recommended core and path the
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
