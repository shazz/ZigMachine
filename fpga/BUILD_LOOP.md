# The edit -> board loop: what a bitstream costs, and how not to pay it

Matt's rule: **a full SoC rebuild only when it is needed.** `README.md` "When is a full
rebuild needed" is the decision table; this file has the measurements behind it and the
tools: `flow.mk`, `soc/openxc7_fast.py`, `tools/build_times.py`, `tools/sweep.py`,
`tools/pnr_slot.sh`, `tools/freeze_placement.py` and `soc/zm_hp_test*.py`.

## Where a build's time goes

Every openXC7 build prints its stages and appends a line to `build/build_times.txt`.
`tools/build_times.py` gets the stage wall times from `stages.txt` and nextpnr's own split
from `pnr.log`, with every clock's fmax and, for a REUSE build, the number of pinned cells.
Measured 2026-10-03 on the pass-3 board netlist (9.4 k cells to place; `build/flow/p3/`,
`fpga/build/fable_timing3/logs/cdc_s*.log`), often while other agents' Verilator runs held 4-6
of the 8 cores:

| stage | time | what it is |
|---|---|---|
| gen | seconds | LiteX elaborates the SoC and writes the Verilog, XDC and script |
| synth | 44-65 s | Yosys `synth_xilinx`, single-threaded |
| place: HeAP | **52-66 s** on a quiet box, 150-240 s under load | analytic placement + legaliser + congestion spreading; 2 threads (the x and y solves) |
| place: refine | 18-116 s | simulated annealing, single-threaded (`--parallel-refine`: 17 s) |
| route | 31-65 s | router2, which runs its quadrants on threads by itself |
| rest of nextpnr | ~12 s | chipdb load, packing, delay matrix, timing report, JSON/FASM out |
| frames + bit | 16-21 s + 0.1 s | fasm2frames (Python), xc7frames2bit |
| **total** | **4-6 min** | placement is 55-70 % of it |

**The current tree is worse.** Today's board netlist places 15 k cells, not 9.4 k: the
CDC queues now keep their entries in flip-flops (`soc/zm_cdc.py FF_STORAGE`, a board-debug
change, +4.3 k FFs and their read muxes). On it, HeAP stalls in legalisation at iteration 6 (a
reference build stopped after 10 min; another build ran 52 min). `soc/openxc7.py` now cuts
nextpnr at `OPENXC7_PNR_TIMEOUT` (1500 s). The 4-6 min above is the netlist with LUTRAM queues;
that `FF_STORAGE` is the whole cause of the stall has not been measured.

## Placement replay (REUSE)

`make soc-dev` builds with **stable names** (`OPENXC7_STABLE=1`: Yosys `autoname` names each
cell after the nets it drives) into `build/soc_dev`. The next `make soc-dev`
**replays** that placement (`OPENXC7_REUSE=build/soc_dev/gateware`). Between synthesis and P&R,
`tools/freeze_placement.py` compares the old and new Yosys netlists cell by cell (name, type, and
every port's net by name) and pins the cells that did not change (`-o preplaced=`). A slice is
pinned whole or not at all, and no cell of a packer cluster is pinned (MUXF7/8, CARRY4, LUTRAM,
SRL, the LUTs that feed them). Each rule fixes a nextpnr ERROR found while testing on edited
netlists: pinning by name alone broke a carry chain ("cluster member ... needs bel ..., which
... holds"), and pinning half a slice broke it ("Bel ... A5FF is not valid for cell ...").
`FRESH=1` starts a new base.

**What it buys, measured.** The test was a small, typical edit: a 32-bit debug counter on a
new `zm_glass_regs.v` register (`build/flow/p3/`).

| | cells unchanged | pinnable safely | result |
|---|---|---|---|
| the same netlist again (`same_final`) | all | 17,075 of 17,075 | place 2.5 s instead of 174 s; P&R 64 s instead of 226 s; whole build 152 s instead of 296 s; fmax 108.4 / 140.5 against 110.9 / 133.7 |
| edit, flat synthesis (`edit_final`) | 5,381 of 14,392 (37 %) | 1,156 (7 %) | routes cleanly, but no gain: P&R 256 s against 226 s; fmax 89.0 / 119.2, because the edit redraws the seed lottery |
| edit, kept module hierarchy (tried, dropped) | ~7,700 | 3,858 (20 %) | the base gets worse: 10.4 k cells to place, P&R 23 min under load, comp 118.9 MHz (fail) |

**Why so little survives.** Yosys numbers every internal object from one global counter,
and ABC maps logic in that order. An edit anywhere renumbers everything after it, so ABC
re-maps logic that did not change. VexRiscv was kept as its own hierarchy and was not
touched, and 840 of its 4,817 cells still came out different. Replaying the same netlist
works. Replaying an edited one only pays off once unchanged modules synthesise to the same
cells. **Next step:** synthesise each RTL module in its own Yosys run with the counter reset
(`autoidx`), cache it by its sources' hash, and stitch the results at the top. That would also
skip re-synthesising VexRiscv. Until then, `make soc-dev` is safe (it never fails a build that
would otherwise pass), but for an edit its time is a full build's.

## Threads

nextpnr-himbaechel's `--threads` drives only `--parallel-refine` and the static placer.
HeAP already runs its x and y solves on two threads, and router2 splits the die into
quadrants and routes them on threads by itself, so neither has a knob. `OPENXC7_FAST=1`
(soc/openxc7.py `FAST_OPTS`: `--parallel-refine --threads 4`) swaps the annealer for the
parallel refiner. On the same netlist and seed this took refinement from 21.6 s to 17.2 s, and
fmax went from 110.9 / 133.7 to 112.5 / 138.6 MHz (sys / comp). The annealer's time swings
between 18 and 116 s from run to run, and on those runs the parallel refiner saves the most. It
is opt-in for dev builds. It changes the placement a seed gives, so the release build and its
sweep never use it: a seed found with FAST would not reproduce in `make soc-z7`.

## Seed sweeps

`make sweep SEEDS="1 2 3 4"` (`tools/sweep.py`) places and routes the last `make soc-z7`
netlist (or `SWEEP_SRC=<gateware dir>`) once per seed. Each seed gets `build/sweep/<top>/s<N>/`
and runs the same flow as the release build: no REUSE, no FAST, so the seed it finds reproduces.
It runs **two seeds at a time** through `tools/pnr_slot.sh`, cuts any seed at `--timeout`
(900 s: a router that never converges, like pass 3's `cdc_s8` or the 1,200 s `soc_z7_wq2` run,
costs one slot, not the sweep), produces a .bit per seed and prints the seeds best first (all
clocks passing, then the worst fmax/target). Pin the winner in `soc/openxc7.py SEED` and use
its bit as it is.

Speed-up: with both slots free, N seeds take ceil(N/2) P&R times instead of N, so about 2x on
the 8-core box. HeAP and the annealer use one or two cores, and router2 uses its quadrant
threads. **Not measured on an idle box:** every slot this session shared the machine with
other agents' builds and Verilator runs, and under that load one P&R's HeAP took 150-240 s
against 52-66 s on a quiet box. On a loaded box the gain is smaller than 2x.

## hp-test

`make hp-test` (`soc/zm_hp_test.py`) puts only the PS7's HP0/HP1 and GP0 in the PL.
Behind them sit the SoC's own `WishboneHP` and `ZMVideoAXI`, plus a raw AXI engine per port
with LEN/SIZE/CACHE/STRB/LANE from registers. U-Boot probes it with `mw`/`md`
(`boards/microphase_z7_7010/README.md` "hp-test"). Simulated in `tests/test_hp_test.py`
against the DDR model, including the WR32 upper-word loss and a read outside the window.

Build, measured: synth 12 s, place 41 s, **route 364 s** (7.2 min, 106.4 MHz). That misses the
1-min target, and router2 is the whole reason: ~2.1 k flops and 3.3 k LUTs in a 30-column band
next to the PS7 start at 8 k overused wires. The SoC's timing weight of 30 never finished
(900 s cap), and `--placer-heap-beta 0.5` did not help. At timing weight 10 it routes
(`flow.mk HPT_PNR`). The bitstream changes only when the bridges do, so it is built once and
each DDR/AFI question after that costs seconds. Next step for the build time: register the HP
ports at the PS7 edge and/or pull the 4 status/compare engines into one shared one.

## Containers

Every P&R goes through `tools/pnr_slot.sh`: at most **two** openXC7 containers (6 GB each)
on the 15 GB / 8-core box. Slot 0 is `build/fable_timing3/.container.lock`, the lock every
other P&R target already takes, so those still serialise against each other; slot 1 is the
second container. `docker run --init` (tools/openxc7.sh) lets a killed build stop its
container. Without it the container kept running nextpnr with nothing waiting for the result.
