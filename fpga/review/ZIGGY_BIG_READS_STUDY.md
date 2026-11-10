# ZIGGY and big reads: where a refill's cycles go, and what to cut

Study, 9 Nov 2026, branch `study/ziggy-big-reads`. Matt: "kestrel is better at ram writes but really
slower at ram big reads, can we improve that? ... we need to be better :D".

**Recommendation: build `--ziggy-reads prefetch` and A/B it on the board** (about +60 LUT, no BRAM,
no CSR change, no core regeneration). In the core harness it takes a 192 KB read from 46.9 to
**87.2 MB/s (x1.86)** and a 64 KB copy from 38.6 to **66.1 MB/s (x1.71)**, and every miss, random
ones included, gets 7 clocks cheaper. If the A/B shows no fps change on any cart, `--ziggy-reads fast`
alone (+25 LUT) keeps the per-miss part. Nothing else on the candidate list beats it per LUT.

## The board today

The board's ZIGGY is `VexRiscv_I16w2D16w2SealFpuZmxE` (KESTREL v1/combo16: I$ 16 KB 2-way, **D$ 16 KB
2-way**, not 4 KB), on HP0 through WishboneHP with posted stores (8) and **no read bypass** (Matt, 4 Nov:
"drop the bypass"). Bench cart (board): 256 KB read 43 MB/s, 4 KB read 120.6 MB/s; BENCH_REPORTS.md:
`ld.miss.64K` 48.26 cycles a line, `ld.seq.64K` 7.19 cycles a word. The D$ is blocking: one refill at
a time, and the load waits for the whole line.

## How it was measured

- **The core harness** (`tests/test_ziggy_reads.py`, new): the board's cart netlist in Verilator over
  the SoC's own pieces: LiteX's shared Wishbone (Arbiter + Decoder), WishboneHP (posted=8, no bypass),
  the HP register slices (`zm_board_mem.hp_slice`'s shape) and `ZMSimAXIRAM` (the hp_sim DDR model)
  with its AR-to-first-beat latency. `tests/zigread/reads.c` runs the bench cart's own 8x-unrolled
  read/write/copy loops (apps/c/bench/kestrel/k_mem.c), a bare line-miss loop, random line reads and
  a store-then-stream coherence kernel; every bridge variant must read the same checksums.
  ~1 s a run once built, so the sweep ran on omarchy (Verilator 5.052).
- **Calibration.** At latency 20 (hp_sim's HP_LATENCY) the bare miss loop costs 49.2 cycles a line
  (board `ld.miss`: 48.3) and the 192 KB read 46.9 MB/s (board 256 KB: 43). Latency 24 gives
  44.2 MB/s, so the board's PS round trip is about 22-26 clocks; both columns are below.
- **A VCD of one miss** (the harness's `--trace` build, `ZM_TRACE=<cycle>,<n>`) gave the breakdown.
- LUT: Yosys `synth_xilinx` of WishboneHP alone in each mode (`tools/hp_read_synth.py`), then
  Vivado on the full board bitstream (below).

## Where a refill's 45 clocks go (base, latency 20)

| clock | event | who | cost |
|---:|---|---|---:|
| 0 | the load misses; the D$ puts the refill on the Wishbone (CYC) | core | |
| +1 | WishboneHP registers ARVALID | bridge | 1 |
| +2 | the HP slice registers it at the PS7 pin | slice | 1 |
| +24 | first R beat at the PS7 pin | **PS + DDR** | **22** |
| +25 | the inbound slice | slice | 1 |
| +27 | the beat in the line buffer (+1), first ACK (registered, +1) | bridge | 2 |
| +41 | the 8th ACK: **two clocks a word** (`req` drops while the registered ack is high) | bridge | 14 |
| +42 | the D$ takes the last word (rsp is a RegNext in `toWishbone`) | core | 1 |
| +45 | the D$ loader finishes, the load replays, the pipeline moves | core | 3 |

**22 of the 45 clocks are the PS and the DDR; 23 are ours** (2 slices, 3 bridge registers, 14 of word
delivery, 4 in the core). The bandwidth is not the wall: four 64-bit beats come back on four clocks.

## The options, ranked

| # | Option | Gain (harness, latency 20) | Cost | Verdict |
|---|---|---|---|---|
| 1 | **Burst acks one a clock** (`fast_burst`, zm_hp_read.py): the bridge answers the next word of an incrementing burst the clock after an ACK, since VexRiscv's D$ and I$ advance their address on ACK | -6.6 clocks on EVERY miss: 192 KB read 46.9 -> 52.6 MB/s, copy 38.6 -> 42.3, random lines 59.1 -> 52.3 c/load, I$ refills too | Yosys +25 LUT, 0 FF | **Do.** No coherence question: same data, earlier |
| 2 | **Next-line prefetch** (`prefetch`, zm_hp_prefetch.py) into the existing line buffer, triggered when a refill ends and is sequential | 192 KB read -> **87.2 MB/s**, copy -> **66.1**, bare miss 42.6 -> 33.9; random unchanged | Yosys +33 LUT on top of 1, +43 FF, no BRAM | **Do (with 1).** The big one for streams |
| 3 | 64-byte D$ lines (vexgen `bytePerLine`) | Halves the misses of a stream, but every random miss doubles its delivery and the D$ holds half the lines: texture carts lose | Core regen + timing re-close; line buffer 512 FF | No: 2 gives the stream gain without the random-read loss |
| 4 | Critical word first | Nothing: VexRiscv's D$ loader replays the load only after the whole line | Core change | No |
| 5 | Several refills in flight / hit-under-miss | Would hide the 22 PS clocks for two streams | VexRiscv's DataCache is blocking by design: a new non-blocking D$ (MSHRs, a refill queue; NaxRiscv-class), est. 1,000+ LUT | No at 89 % LUT |
| 6 | Bigger D$ (8/16 KB) | Already done: the board is D$ 16 KB 2-way since KESTREL v1 (roto128 24.5 -> 13 c/px, voxel256 1.81 -> 0.92 Mc). It changes working sets, not streams: a 256 KB read misses every line on any D$ | — | Done |
| 7 | Drop the HP slices on AR and R | -2 clocks a miss (-4 %) | The slices exist so every PS7 pin meets one flop (zm_board_mem.hp_slice); at 89 % LUT the PS7 paths are the risk | Not now; worth one Vivado try if timing has margin |
| 8 | Software: touch-ahead loads | Nothing: a touch is a blocking miss too | — | No |
| 9 | Software: CHISEL copy into a cart buffer | The data lands in DDR again, the CPU still misses on it | — | No (only a TCM/BRAM target would help; no BRAM to spare) |
| 10 | Two-stream prefetch (a second buffer, one stream each) | Would give 2's gain to two-stream loops (the FRESCO planner's `cmpcpy`, a blend of two images) | ~+130 LUT, and it lets a load pass an older load to another line: legal under RVWMO only with a FENCE r,r between a flag read and its data, which the firmware and carts do not emit | Later, only with a memory-model decision |

## The prefetch's contract

A prefetched line is a DDR read made right after the refill that triggered it. Serving it later is
the same as the CPU having made that refill at the prefetch's time, which is correct as long as the
CPU learned nothing newer in between. ZIGGY learns about the other masters (CHISEL's writes to cart
RAM, the ARM's disk reads, BARD) only through the bus or an interrupt, so the line is dropped on:

- **a store to its line**: the line buffer's own rule now (a store's ack closes the buffer of its own
  line; a store to another line no longer does, which is what lets a copy keep its prefetched source);
  before the AR, the AR waits for the posted stores to drain like any read;
- **any IO access by the CPU, or a pending interrupt** (`io_kill`, wired in `zm_board_mem.add_cpu_memory`
  from the D-bus before the IO fence and `cpu.interrupt`): every CHISEL start/status, CSR and mailbox;
- **any other read**: it takes the (single) buffer, so a flag read cannot be followed by a stale line.

Proofs: `tests/test_hp_prefetch.py` runs a model port whose memory another master rewrites, for each
rule (store, IO, other refill) and with nothing in between (served, as it should be); ZM_RTL_BREAK=1
builds `noadvance`, `nostore` and `noio` and each serves a wrong word. The core harness's
store-then-stream kernel catches `nostore` with the real core. Every bridge test (posted, bypass,
IO fence, board mem, sound regs) passes; `test_io_fence`'s abandoned-burst case is what showed the
store rule must stay per line.

## Numbers (core harness, cycles and MB/s at 100 MHz, 1 MB = 2^20 B)

| kernel | base @20 | fast @20 | prefetch @20 | base @24 | fast @24 | prefetch @24 |
|---|---:|---:|---:|---:|---:|---:|
| write 256 KB | 179.2 | 179.3 | 179.3 | 179.2 | 179.3 | 179.3 |
| read 4 KB x16 (D$ hits) | 137.7 | 140.6 | 150.2 | 136.1 | 139.0 | 148.3 |
| **read 192 KB** | **46.9** | 52.6 | **87.2** | **44.2** | 49.2 | **78.2** |
| bare line miss (c/line) | 49.2 | 42.6 | 33.9 | 52.9 | 46.3 | 37.6 |
| **copy 64 KB** | **38.6** | 42.3 | **66.1** | **36.7** | 40.1 | **66.1** |
| random lines (c/load) | 59.1 | 52.3 | 52.3 | 62.8 | 56.0 | 56.1 |

The prefetch is issued when a refill ends, so it hides the PS latency behind the CPU's work on the
line it just got: the bench read loop (~22 clocks a line) hides almost all of it; a faster loop (the
bare miss loop, one load a line) hides part. The copy gains the most for its cost: without the
bypass, every refill used to wait for the previous line's stores to drain, and a prefetched line
needs no AR at all.

## LUT and timing

| mode | Yosys (bridge alone) | Vivado, full board bitstream | sys WNS |
|---|---|---|---|
| base | 226 LUT, 405 FF | not built here; reference: the lead's desk-bars build of 9 Nov (same CSR map), 15,716 LUT (89.3 %), sys WNS -0.041 ns | -0.041 |
| fast | 251 (+25), 405 | — | — |
| prefetch | 284 (+58), 448 (+43) | **not built yet**: `fpga/build/board_reads_pf.sh` (waits for a quiet box) | ? |

The risk is timing, not LUTs: in the lead's 9 Nov build the paths phys_opt kept working on run
from the I$ into WishboneHP's `ack` and the AR length mux, and `fast_burst` adds a 3-bit increment and
a mux in exactly that cone. If sys misses, try `--ziggy-reads prefetch` with `fit_netdelay`, or
register `cont` a clock earlier.

## What it changes for real carts

- **Sequential readers gain most**: anything that copies or scans cart RAM in order: the CPU's
  memcpy/word copies out of cart RAM (sprite/tile copies, unpacked frames, scrollers that copy rows),
  ZX0/ICE depacking (the packed stream is read in order), stniccc's scene stream, table walks.
  These are the carts the bench's 256 KB read stands for.
- **Random readers get the per-miss part** (-7 of ~45 clocks): texture mappers (roto256, voxel256: the
  misses the 16 KB D$ still leaves), lookups in big tables.
- **Two-stream loops get only the per-miss part**: the FRESCO planner's row compare (`cmpcpy`, the
  ~0.33 Mc a static plane costs) alternates its two rows line by line, so its refills are never
  sequential (option 10 would cover it).
- **BARD** shares WishboneHP (soc/zm_sound_cpu.py) but keeps the base path: `fast_burst` would cut its
  misses the same way; a separate A/B (players' load on the OSD) if this one is kept.
- Pixel and sample exactness: the bridge returns the same words in the same order; only the time
  changes. The checksums in the harness and the unit tests' data checks pin it.

## Board A/B (for the lead)

- A: the board's current bitstream (or `--ziggy-reads base` from this branch). B:
  `fpga/build/board_reads_pf/gateware/platform_z7.bit` once `fpga/build/board_reads_pf.sh` has run
  (`--ziggy-reads prefetch`, otherwise the combo16 command line: `--blit --sound-cpu --posted 8
  --no-read-bypass`, `VexRiscv_I16w2D16w2SealFpuZmxE`, BARD `SndNdD16Dyn8Sx`, `fit_timing`).
  The CSR map is combo16's (same csr.json): no firmware rebuild.
- Measure: the BENCH cart's `mem_read_256k` / `mem_copy_256k` / `mem_memcpy_256k` (expect ~43 -> ~75
  MB/s on the read), and OSD fps on the carts the 10-18 table shows below 60.

## Not done

- hp_sim of the bench cart: its RAM job runs after the CPU jobs, past 6 frames; and this box's build
  lock was the lead's while the images would have been built. The core harness is the real core on the
  real bridge and slices; what hp_sim would add is the rest of the SoC around them.

## Board fit attempts (10 Nov 2026): PARKED

The 7010 is full (desk-border build: 16,958 LUT after synthesis, 4,400/4,400 slices). Every attempt below starts
from combo16's command line (`build/board_reads_pf.sh`, ignored build dir; scripts recorded here).

| Build | Synth LUT | Result |
|---|---:|---|
| prefetch | 16,999 | placement failed (unplaced instances) |
| prefetch, retry `AltSpreadLogic_high` | 16,999 | placed, WNS -3.73 ns, 3,334 failing |
| prefetch + `bus_timeout=None` (`ZM_BUS_TIMEOUT=0`, soc/zm_z7.py) | 16,987 | placement failed: the timeout cut is only -12 LUT |
| fast + `bus_timeout=None` | 16,880 | placement failed, though smaller than the build that fits |
| fast + `bus_timeout=None`, retry: placer `Explore` (first of Explore / ExtraPostPlacementOpt / WLDrivenBlockPlacement / EarlyBlockPlacement / SpreadLogic_medium / Default) | 16,880 | placed, WNS -3.35 ns (clkout0 -1.84, clkout1 -1.91), 3,147 failing, 83 % route delay: congestion |

Conclusion: at 100 % slices, fit is placer luck; cuts of tens of LUT do not change it. Only a few hundred LUT
(and their slices) freed would. Matt (10 Nov) rejected the CHISEL QUEUE ring and pixel-queue (LQ 5 -> 4) cuts and
parked the RAM-read hardware: revisit with a real cut (POKEY ~270, hardware PCM ~650 if unused) or a 7020.
The retry Tcl: from `board_reads_fast_nto/gateware/platform_z7_synth.dcp`, `opt_design -directive ExploreArea`,
`opt_design -control_set_merge -merge_equivalent_drivers`, then each placer directive until one places,
`phys_opt AggressiveExplore`, `route NoTimingRelaxation`, `phys_opt AggressiveExplore`.
