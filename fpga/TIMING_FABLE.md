# Closing timing on the Z7-Lite under openXC7 (Fable, pass 1, 2026-10-02)

> **Pass 2 (2026-10-03) is done:** the board build meets sys 100 / comp 125 MHz
> with a pinned seed, the compositor on its own clock, and static prediction
> kept (no prediction costs more cycles than it buys clock). Results and the
> current flow: `fpga/README.md` "Timing under openXC7", `fpga/CYCLES.md`
> "Branch prediction and the clock", `docs/FPGA_STEPS.md` 2026-10-03.

Scope: the glass SoC (`soc/zigmachine_soc.py --target z7`, PS7 + GP0 + DDR-framebuffer
video) on the XC7Z010-1 through the pinned openXC7 image (Yosys 0.67, openXC7/nextpnr
`c68c1358`: a **himbächel** build behind a 48-line `nextpnr-xilinx` shim). Everything was
run from copies under `build/fable_timing/` (`soc/`, `soc_comp/`, `soc_nto/`, `rtl/`,
`vexgen/`; scripts `run.sh`, `pnr.sh`, `synth.sh`, `chain*.sh`; logs in `logs/`; every
result line appended to `results.txt`). No file under `fpga/rtl/`, `fpga/soc/`,
`fpga/vexgen/` was edited. **`chain.sh` … `chain7.sh` are still running one container at a
time (6 GB cap); their lines land in `results.txt` as they finish** — the "pending" rows
below are those.

## 1. Ranked actions

| # | Action | fmax gain (sys) | Effort | Risk | Files |
|---|---|---|---|---|---|
| 1 | **Drop `-abc9`** from `synth_xilinx` (plain `-flatten`) | **92.8 → 105.7 MHz** measured, seed 1 | 1 line | Low: +13 % LUTs (6,070 vs 5,344), uses MUXF7/8; synth 2× slower | `soc/platform_z7.py` (or the LiteX `yosys_nextpnr` synth options) |
| 1b | or keep abc9 and add **`-dff`** | 92.8 → 103.3 measured, seed 1 | 1 line | Low: −1.5 % cells | same |
| 2 | **`--placer-heap-timingweight 30`** | 92.8 → 100.3 measured, seed 1 | 1 token | Low; combination with #1 pending (`noabc9_tw30`) | `soc/openxc7.py` `PNR_OPTS` |
| 3 | **`--router2-bb-budget --router2-slack-order`** | 92.8 → 96.1 measured, seed 1 | 1 token | Low; combination pending (`*_tw30_bb`) | `soc/openxc7.py` |
| 4 | **Register the snoop's delivery + precompute the window selects** (the critical path once #1 is in: FIFO `dout` → `zm_video_comp.v:71 reg_sel` → 32-word CE tree, 9.4 ns, 7.6 routing) | est. +5–10 (H) | 15 lines | Low: one more cycle before `drained`, covered by the drain rule | `soc/zm_video_snoop.py`, `rtl/video/zm_video_comp.v` **(framebuffer agent)** |
| 5 | **`bus_timeout=None`** (the 20-bit timeout counter → forced `shared_ack` is the baseline's critical path, `platform_z7.v:1284-1291`) | est. +3–6 (H); measured run pending (`std150_notimeout`) | 1 line | A hung slave hangs the CPU instead of an error; the seal traps bad addresses first | `soc/zigmachine_soc.py` **(framebuffer agent's file)** |
| 6 | **Freeze the best placement** with `-o preplaced=` (fork feature) | removes the ±6 % seed lottery (90.2–96.1 over seeds 1–4) | script | Medium: must be regenerated when the netlist changes | `soc/openxc7.py`, a `tools/` script |
| 7 | VexRiscv: `prediction=NONE` / `DYNAMIC_TARGET`, `injectorStage`, `dBusRspSlavePipe`, `twoCycleRam` | pending (`cpu_*` builds, 5 netlists in `build/fable_timing/vexgen_out/`) | generator flags | Medium: cycles/frame change, re-run CYCLES.md | `vexgen/src/main/scala/zm/GenZm.scala`, `vexgen/gen.sh` |
| 8 | Compositor on its own clock | pending (`comp150_sys100` probe) | ~150 Migen lines of CDC | Medium | `soc/zm_video_pipe.py`, `zm_video_dma.py`, `zm_video_snoop.py`, `zigmachine_soc.py` **(framebuffer agent)** |
| 9 | Vivado hybrid (Yosys EDIF → Vivado P&R) | H: 125–150 | install | Disk: does not fit in 32 GB free | — |

Measured = a routed `from297_clk` figure from a log in `build/fable_timing/logs/`. H = hypothesis.

## 2. What openXC7/nextpnr can do that we don't use (from the sources)

Checked in the container (`nextpnr-xilinx --help`, `-o help`) and in the pinned sources
(`himbaechel/uarch/xilinx/{xdc,xilinx,xilinx_place,hold_fix}.cc`, `common/kernel/sdc.cc`,
`docs/xilinx-porting/*`).

- **Placer**: `--placer heap|sa|static`; HeAP is timing-driven by default (`--no-tmdriv`
  to disable), knobs `--placer-heap-timingweight` (default 10 — **30 gave +7.5 MHz**),
  `--placer-heap-critexp` (default 2; old nextpnr-xilinx hard-coded 7 — 4 changed nothing),
  `--placer-heap-alpha/beta`, `--placer-heap-congestion-spread [-weight]` (we pass it),
  `--parallel-refine`, `--seed`/`-r`.
- **Router**: router2 + `--tmg-ripup` (tried before, no closure); fork additions
  `--router2-bb-budget [-max]`, `--router2-slack-order` (**+3.3 MHz**), `--router2-smooth-*`
  (post-route congestion smoothing, off), `--router2-cong-mult`, `--router2-alt-weights`;
  `-o hold-fix` (off by default).
- **Constraints honoured** (`xdc.cc`): exactly `set_property` (on `get_ports` and on a
  single `get_cells` name, `-hier` accepted), `create_clock` and `set_multicycle_path -setup
  -to`. `set_max_delay`, `set_false_path`, `-from`, `[current_design]` are skipped with a
  warning; the generic `--sdc` parser's own log says `set_false_path` "does not do anything
  (yet)". **No pblocks, no region attributes.**
- **Placement constraints that work**: `set_property LOC SLICE_XnYm [get_cells <name>]` on
  any cell (`xilinx.cc:apply_loc_constraints`, bound `STRENGTH_LOCKED`, squatters evicted),
  the generic `(* BEL = "..." *)` attribute, and — the useful one — **`-o preplaced=<file>`**
  (`xilinx.cc:640`): pin every cell named in the file to the BEL it had in a reference
  build (`scripts/routing_dump.py` from that build's `--write` JSON); `-o prerouted=` does
  the same for nets. New cells are placed normally (`xilinx_place.cc:605`). This is the
  closest thing to a floorplan openXC7 offers.
- **Yosys**: `-retime` (old ABC `-D 1`, replaces abc9: **77.5 MHz, a loss**), `-dff`
  (**103.3**), `-widemux N` (pending `y_dff_wm`), and plain `abc` (**105.7**).

## 3. The paths

Every path is 6–13 LUTs with 75–85 % routing; the placer's pre-route estimate is 15–20 %
above the routed figure (111.5 → 92.8 on the baseline): **the router loses what the placer
promised**, so flow options that spread cells or weight timing pay more than logic surgery.

- Baseline (registered snoop tap, already in the tree): `builder_count[13]` → `(count ==
  0)` → forced `shared_ack` → `socbushandler ack` → DMA/CPU ack cones, 10.2 ns, 7.9 routing,
  (45,81)→(108,10). Action #5.
- No-abc9 build: snoop FIFO `dout` → `zm_video_comp.v:71-72` `reg_sel/pal_sel` → `zm_video_regs.v:49`
  32-word byte-enable tree, 9.4 ns. Action #4.
- Snoop removed (earlier probes): VexRiscv I$ decode → static prediction → `fetchPc`
  (10.0 ns) on the standard core; `memory_arbitration_isValid` → DivPlugin counter → fetch
  halt → `when_Fetcher_l133/l160` (11.7 ns) on the sealed `relaxpc` core. Action #7:
  `prediction=NONE` removes the first, `injectorStage` cuts the second a stage earlier;
  `GenFullNoMmuMaxPerf` (200 MHz on Artix-7 under Vivado) uses `DYNAMIC_TARGET`.
- The compositor's `start` cones (`zm_video_plane.v:57,79`: `base + row*stride + hs`,
  `py*101 + seed*7`) never appeared in a critical path here — hygiene until the compositor
  runs on a faster clock.

## 4. Experiments (all `--sys-mhz 150`; nextpnr's fmax does not depend on the target)

Baseline for pass 2: **`std150_regtap` = LiteX `standard` core, registered snoop tap
(current `soc/zm_video_snoop.py`), `synth_xilinx -flatten -abc9`, nextpnr
`--placer-heap-congestion-spread --seed 1`: 92.83 MHz** (`logs/std150_regtap.log`,
netlist `out/std150_regtap/platform_z7.json`, bitstream alongside).

| Run | Change vs baseline | Seed | fmax |
|---|---|---|---|
| `m_std150` (earlier, unregistered tap) | — | 1 | 79.44 |
| `std150_regtap` | registered tap (baseline) | 1 | **92.83** |
| `seed2` / `seed3` / `seed4` | seed only | 2/3/4 | 90.16 / 96.08 / 93.79 |
| `tw30` | `--placer-heap-timingweight 30` | 1 | **100.28** |
| `critexp4` | `--placer-heap-critexp 4 --placer-heap-timingweight 20` | 1 | 92.84 |
| `bbbudget` | `--router2-bb-budget --router2-slack-order` | 1 | 96.11 |
| `y_retime` | `synth_xilinx -flatten -retime` | 1 | 77.52 |
| `y_dff` | `synth_xilinx -flatten -abc9 -dff` | 1 | **103.32** |
| `y_noabc9` | `synth_xilinx -flatten` | 1 | **105.71** |
| `sealrpc150_regtap` | sealed I16w2D4 + relaxpc core | 1 | pending |
| `cpu_Nopred` / `cpu_Dyn` / `cpu_Inj` / `cpu_InjDrsp` / `cpu_DynInjDrspTcr` | sealed+relaxpc + the flag(s) | 1 | pending |
| `comp150_sys100` | compositor on its own 150 MHz PLL output (`soc_comp/`, timing probe, no CDC logic) | 1 | pending |
| `std150_notimeout` | `bus_timeout=None` (`soc_nto/`) | 1 | pending |
| `tw60` / `tw100` / `tw30_seed2` / `tw30_seed3` / `tw30_ce7` / `tw30_nospread` | timing-weight sweep | | pending |
| `tw30_bb`, `dff_tw30`, `dff_tw30_bb`, `dff_seed3`, `y_dff_wm`, `noabc9_tw30`, `noabc9_tw30_bb`, `noabc9_seed3`, `y_noabc9_dff` | combinations | | pending |

Reproduce any row: `cd fpga/build/fable_timing; SEED=n ./pnr.sh <netlist-tag> <name> <nextpnr opts>`
(P&R only, ~4 min), `./synth.sh <src> <new> "<synth_xilinx opts>"`, `./run.sh <tag> <soc args>`
(full flow; `PKG=soc_comp OUTDIR=soc_comp` or `PKG=soc_nto OUTDIR=soc_nto` for the variants).

## 5. Clocking: must CPU, bus and compositor share one clock?

No, and the budget says they should not. `rtl/video/README.md` ("Throughput"): compositor
busy clocks per frame — `tutorial` 0.73 M, `dhs_0pxl0reg` 0.62 M, `union_main` (3 planes)
2.24 M, synthetic `worst` 3.52 M. With the DDR framebuffer the CPU **waits between passes**,
so CPU and compositor cycles add in the same 16.7 ms: at one 93 MHz clock (1.55 M/frame)
`union_main` does not fit at all; `tutorial` leaves 0.82 M for a cart needing 0.47 M. The
CPU alone needs skystrike 119 MHz p95, ulm_dsots 112, union_beatdis 61 (CYCLES.md). So the
constraint is `T_cpu(f_sys) + T_comp(f_comp) ≤ 16.7 ms` with two independent levers. The
compositor already crosses to `pix` by toggle synchronisers; a `comp` domain needs the
snoop queue as an `AsyncFIFO`, the sequencer CSRs/`cmd` strobe through
`BusSynchronizer`/`PulseSynchronizer`, and the DMA request/response ports as async FIFOs
(~150 Migen lines, no change inside `zm_video_out.v`). What it does not fix: the CPU still
needs ~120 MHz for skystrike. The in-situ compositor fmax is the pending `comp150_sys100`.

## 6. Is Vivado worth it?

What changes: real timing-driven P&R + `phys_opt_design` (replication, fan-out splitting on
the cones in §3), `set_max_delay -datapath_only` honoured on the crossings, pblocks for
`VexRiscv` and `zm_video_out` (the 30–60-row spread), and a timing report that is not an
estimate. Expectation (hypothesis): 125–150 MHz for this 8.7 k-LUT netlist on a -1 part;
public LiteX boards close VexRiscv `standard` at 100–150 under Vivado. **Hybrid flow is
built into LiteX**: `XilinxVivadoToolchain(synth_mode="yosys")` reads our Yosys EDIF
(`litex/build/xilinx/vivado.py:326`: `read_edif` + `link_design`, then
`opt/place/phys_opt/route`), so synthesis stays reproducible and only P&R moves. Size: a
Zynq-7000-only ML Standard install is reported between ~40 GB (2024.x, 7-series only ≈ 70)
and ~80 GB (2023.1 guide, Zynq-7000 + ZU+); **it does not fit in the 32 GB free here**.
Options: a second disk at `/opt/Xilinx`, or a one-shot VM (4 vCPU, 16 GB, 100 GB, ~1 h) fed
the EDIF + XDC and returning a `.bit` + timing report.

## 7. Pass 1: apply now

Baseline to compare against: `std150_regtap`, seed 1, **92.83 MHz** (§4). Measure each
change at `--sys-mhz 150`, seed 1, `--placer-heap-congestion-spread`, and quote the last
`Max frequency for clock 'from297_clk'` line; one run is ±3 MHz, so re-run seed 3 for any
gain under 5.

**P1-1. Synthesis: no abc9** — measured +12.9 MHz (105.71, seed 1). In
`soc/platform_z7.py` (or wherever the openxc7 platform's synth options are set — LiteX's
`yosys_nextpnr.py` builds the line `synth_xilinx -flatten -abc9 -arch xc7`), drop `-abc9`,
i.e. set the toolchain's `_synth_opts`/`yosys_template` so the `.ys` line reads
`synth_xilinx -flatten -arch xc7 -top platform_z7`. Alternative with lower area: keep
`-abc9` and add `-dff` (+10.5, 103.32). Verify: `make -C fpga soc` builds; the bitstream is
behaviour-identical by construction (same RTL); `pytest fpga/tests/test_platform_xdc.py`.
Proven netlist: `build/fable_timing/out/y_noabc9/`. Not a framebuffer-agent file.

**P1-2. Placer timing weight** — measured +7.5 MHz (100.28, seed 1). `soc/openxc7.py`:
`PNR_OPTS = "--placer-heap-congestion-spread --placer-heap-timingweight 30"`. No
behavioural change. Verify: the `nextpnr-xilinx` line in `build/soc_z7/gateware/build_platform_z7.sh`
carries it. Combination with P1-1 is the pending `noabc9_tw30`.

**P1-3. Router budget** — measured +3.3 MHz (96.11, seed 1). Add
`--router2-bb-budget --router2-slack-order` to the same `PNR_OPTS`. Combination pending
(`tw30_bb`, `noabc9_tw30_bb`); apply only if those confirm it stacks.

**P1-4. Snoop delivery register + precomputed selects** (**framebuffer agent**:
`soc/zm_video_snoop.py`, `rtl/video/zm_video_comp.v`). Hypothesis +5–10 once P1-1 is in
(its critical path). In `ZMVideoSnoop._deliver`, replace the comb `self.we/waddr/be/wdata
<= fifo.dout` with a `sync` stage (`we` registered as `fifo.readable & due`; `empty` must
include that register: `~fifo.readable & ~tap_busy & ~we_reg`). Push three select bits
(`reg`, `pal`, `beam`, computed at enqueue from `off`, as `snooped` already is) into the
FIFO word (57 → 60 bits) and export them; in `zm_video_comp.v:71-73` take `reg_sel/pal_sel/
beam_sel` from those inputs instead of comparing `cpu_waddr`. Verify:
`pytest fpga/tests/test_video_soc.py fpga/tests/test_rtl_video.py` (the sim path uses the
same snoop; the drain rule means one extra cycle is invisible to the sequencer).

**P1-5. `bus_timeout=None`** (**framebuffer agent's file**: `soc/zigmachine_soc.py:106-116`,
add `bus_timeout=None` to `SoCCore.__init__`). Removes the baseline's critical path;
measurement is the pending `std150_notimeout` (`soc_nto/` is that exact one-line copy).
Behaviour: a Wishbone access to a slave that never acks hangs instead of returning
0xFFFFFFFF + `bus_errors++`; the seal makes that unreachable from the cart. Verify:
`pytest fpga/tests/test_seal_core.py fpga/tests/test_rtl_seal.py`; the LiteX BIOS boots in
`--target sim`.

For pass 2: apply P1-1 + P1-2 (+ P1-3 if confirmed), rebuild, record the new critical path
from the log (`awk '/Critical path report for clock .from297_clk/'`); then P1-4/P1-5
against that number, and read the `cpu_*` and `comp150_sys100` rows for the next pass's
direction.

## Pass 3 (2026-10-03, Fable): the median, the frozen placement, the dynamic predictor

Run from copies under `fpga/build/fable_timing3/` (mirror of `fpga/` with `soc/`, `rtl/`,
`vexgen/`, `tools/` copied, the rest symlinked; `run.sh`, `pnr.sh`, `synth.sh`, `chain1.sh`,
`chain2.sh`, every result line in `results.txt`, logs in `logs/`, heatmaps in `heat/`). Nothing
under `fpga/rtl`, `fpga/soc`, `fpga/vexgen` was edited. **The queued runs were still in flight
when this section was written (hand-back at 10:41): chain1/chain2 append to `results.txt` as
they finish, and `logs/mempath_pass3.log` + `build/mempath/uart/<core>/` carry the cycle runs.**
Summarise a log with `tools/critpath.py LOG...` (fmax, logic/routing split, endpoints, long nets).

### 1. What limits `sys`, seed by seed (pass-2 board netlist, `tools/critpath.py` over seeds 1-12)

| seeds | fmax | the path | fix |
|---|---|---|---|
| 1, 8, 10 | 100.6-102.0 | I$ tag RAMB18 `DOADO` (clk-to-q 2.45) -> way select -> `decode_INSTRUCTION_ANTICIPATED` -> **regfile RAMB18 address** (setup 0.57): 4.4 ns logic of which 3.0 is the two BRAMs, 5.5 routing | `RegFilePlugin(ASYNC)`: the regfile becomes LUTRAM read from the registered decode instruction; the BRAM-to-BRAM floor goes (netlist `VexRiscv_SealRfA`, rows `b_RfA*`) |
| 2, 3, 7, 9, 11 | 90-97 | jump/redo mux -> `fetchPc_output_payload` (fanout 7: 4 RAMB36 + 2 RAMB18 address pins, **2.0-3.0 ns on one net**) -> I$ tag address; 8-9 ns routing | not duplication (fanout 7): the six I$ BRAMs are spread along the one column. Rows `locvex_s*` / `locall_s*` pin them where seed 8 had them; a compact 2-column arrangement is the next XDC to try |
| 4, 5, 12 | 76-90 | **not the CPU**: synchroniser out -> gray->bin XOR chain -> `asyncqueue_level_w` subtract -> `writable` -> consumer push -> the NEXT queue's `rnext`, 3 ns logic + 8-10 ns routing, all one sys cycle (`soc/zm_cdc.py` AsyncQueue; pass-2 `board_pl`/`static_pl` were limited by the same `rd_x_asyncqueue` path) | **P3-1 below**: register the writer's view of the reader pointer |

### 2. `-o preplaced=` crash: root cause, reproducer, workaround

- Reproducer (3.6 s): `pnr.sh` on the board netlist with a one-line file
  `VexRiscv.RegFilePlugin_regFile.0.0<TAB>RAMB18_X0Y38/RAMB18E1` -> `std::out_of_range: dict::at()`
  (`logs/repro_pre1.log`).
- Cause (sources at `openXC7/nextpnr` c68c1358): `pack.cc:1297` calls `apply_preplaced(false)`
  first thing in packing; it resolves the second column with `ctx->getBelByNameStr`, whose
  himbaechel implementation does `tile_name2idx.at(name[0])` (`himbaechel/arch.cc:212`): the
  first component must be a **tile** name (`X<gx>Y<gy>` on the 106x129 grid, e.g. the pad lines
  `X127Y82/IOB_X0Y0.IOB33S.PAD`), and the miss throws instead of returning no bel. Pass 2's
  `placement_static2_s8.tsv` was built from the routed JSON's `NEXTPNR_BEL`, which is the
  Vivado-style `SITE/BEL` (`SLICE_X0Y50/D6LUT`); every line misses. Fork fix: guard the lookup
  (`count()` before `at()`, or accept the site form).
- Workaround that needs no fork change: `-o placement=<json>` (also `fasm.cc:write_placement`)
  dumps `cell -> {tile, site, bel, nextpnr_bel, type}` and `nextpnr_bel` is the tile-qualified
  name. **`tools/freeze_placement.py PLACEMENT.json OUT.tsv [--match PREFIX] [--types ...]`**
  (in the mirror's `tools/`) writes the replay file. Rows `static_s8_place` (the dump),
  `frz_all_s3` (every cell, seed 3: expect seed 8's figure) and `frz_vex_s1..4` (VexRiscv's
  cells only) are the proof runs; `loc_one_probe` checks the XDC `set_property LOC` path
  (`apply_loc_constraints`, site + type -> bel, no tile names involved) as the second freeze.

### 3. Why the dynamic-target core does not route (`logs/dyn_s2_heat.log`, `heat/`)

`--router2-heatmap` writes four CSVs per iteration, so a killed route still tells. The BTB is
three RAMB18E1 (1024x18 TDP, `ram_style=block`), +341 LUTs, +138 FFs over static. The overused
set is **not fixed**: at the 40-90 plateau it churns through VexRiscv's execute/decode nets
(`_zz_execute_SRC1/2_CTRL`, `_zz_decode_RS2`, the barrel shifter, CSR), on SINGLE/DOUBLE wires,
in a band x 15-62 / y 32-54 of the tile grid with the **BRAM column x=40 recurring**. That is
density, not a hard conflict: VexRiscv's cluster straddles the BRAM column and the heap placer
(timing weight 30) packs it past what the local interconnect carries. Pass 2's `dyn_pl`
"95.5 MHz" was the placer's estimate; it never routed either. Experiments queued, P&R only on
the pass-2 dyn netlist, seed 2, 15-min cap (chain2): `dyn_tw10_s2` (timing weight 10),
`dyn_cw2_s2` (`--placer-heap-congestion-weight 2.0`, default 0.5), `dyn_beta75_s2`
(`--placer-heap-beta 0.75`, default 0.9), `dyn_altw_s2` (`--router2-alt-weights`). Smaller cores
(chain1 `b_Dyn*`): `SealDynT8` (BTB 256, 1 RAMB18-ish), `SealDynT8L` (256 in LUTRAM),
`SealDynT6L` (64 in LUTRAM), `SealDynH` (`DYNAMIC`: 2-bit history, no target cache),
`SealDynT8Rfa`. The mirror's `vexgen/src/main/scala/zm/GenZm.scala` + `gen.sh` carry the flags
(`h4/h6/h8`, `btbdist`, `dynh`, `nopb`, `rfa`, `nobyp`, `lsh`, `ebr`, `mulb`, `shearly`).

### 4. Ledger (variant, seeds, min/median/max sys MHz, cycles, routes)

Filled from `results.txt` as rows land; the static baseline is pass 2's sweep.

| variant | seeds | sys min / median / max | comp | cycles vs static (p95, MHz for 60 fps: ub / ulm / sky / tut) | routes |
|---|---|---|---|---|---|
| static board core (pass 2) | 1-12 | 76.1 / 92.9 / 102.0 | 94.9-138.8 | 52 / 98 / 119 / 26 | yes |
| static, seeds 1-4 only | 1-4 | 82.8 / 89.2 / 102.0 | | same | yes |
| `cdc` = static + P3-1 | 1-6, 8, 12 | pending (`cdc`, `cdc_s*`) | | same (no cycle change) | |
| `frz_all_s3`, `frz_vex_s1-4` | 3 / 1-4 | pending | | same | |
| `b_RfA` regfile ASYNC (+P3-1) | 1-4 | pending | | same | |
| `b_NoByp` bypassExecute=false | 1-4 | pending | | pending (`NoByp`, mempath pass3) | |
| `b_Lsh` LightShifter | 1-4 | pending | | pending (`Lsh`) | |
| `b_Ebr` earlyBranch | 1-4 | pending | | pending (`Ebr`) | |
| `b_MulB` MulPlugin in+out buffer | 1-4 | pending | | pending (`MulB`) | |
| `b_DynT8/T8L/T6L/H/T8Rfa` | 1 | pending | | pending (`DynT8`, `DynT6L`, `DynH`; pass-2 Dyn: 47/89/107/22) | |
| `dyn_tw10/cw2/beta75/altw_s2` | 2 | pending | | as Dyn | |
| `locvex_s1-4`, `locall_s1-4`, `nohier_s1-4` | 1-4 | pending | | same | |

Cycle figures: `PYTHONPATH=build/fable_timing3 uv run python tools/mempath_run.py --report-only`
reads them, or `mempath_report.load()` + `mhz(runs, (core, "hp_wc", "aligned", cart))`.

### Pass 3: apply now

**P3-1. `soc/zm_cdc.py` AsyncQueue: register the writer's view of the reader pointer** (proven
in `build/fable_timing3/soc/zm_cdc.py`, `tests/test_video_cdc.py` 5/5 against the copy). Replace
`rbin_w.eq(Cat(*_bin(rgray_w)))` in the comb block by a comb `rbin_w_now` and add
`rbin_w.eq(rbin_w_now)` to `wsync`. One wcd cycle more before the writer sees an entry gone:
`level_w` never under-counts and `empty_w` is late by one cycle, both conservative for the drain
rule; `room = level_w < QUEUE-1` keeps its margin. Removes the 13-ns path that set seeds 4, 5
and 12 (76-90 MHz) and pass 2's `board_pl`/`static_pl`. Tests: `pytest fpga/tests/test_video_cdc.py`,
`uv run python tools/video_sim_run.py` (tutorial + dhs_0pxl0reg hash match), then the seed sweep
(`cdc_s*` rows give the new numbers; re-pin the seed).

**P3-2. Freeze the placement through the dump, not the routed JSON.** Add `-o placement=` to
the board build's nextpnr line (`soc/openxc7.py add_pnr_opts`), ship
`tools/freeze_placement.py`, and replay with `-o preplaced=<tsv>` once `frz_all_s3` confirms the
replay reproduces seed 8. A VexRiscv-only freeze (`--match VexRiscv.`) is the one that survives
edits outside the CPU. Fork bug to report upstream: `apply_preplaced` -> `getBelByName` ->
`tile_name2idx.at()` throws on a site-form name.

**P3-3. `RegFilePlugin(regFileReadyKind = ASYNC)`** in `vexgen/src/main/scala/zm/GenZm.scala`
if `b_RfA_s1..4` beat `cdc_s1..4` at the median: no cycle change, removes the top seeds' floor.
Re-run `make -C fpga vexgen-board`, the mempath `prediction` plan is unaffected.

**P3-4. Dynamic prediction:** apply only the variant whose row routes on 3 of 4 seeds; measure
its cycles (`mempath pass3` plan) before choosing. If none routes, the placer-density knob that
routes `dyn_*_s2` goes into `PNR_OPTS` for that core only.

### Verdict

Not yet at the ceiling: a third of the seeds were limited by one combinational CDC chain outside
the CPU (P3-1, a 4-line patch with tests passing), the best seeds by a BRAM-to-BRAM path a
generator flag removes (P3-3), and the frozen-placement path is now understood (a name-space
mismatch, with a working dump-based route around it) rather than broken. The dynamic predictor's
failure is placement density, which the queued knobs and smaller BTBs address. Vivado remains
the honest next step for skystrike's 119 MHz if, after those land, the median still sits under
~105: openXC7 loses 15-20 % between the placer's estimate and the routed figure and has no
pblocks to hold VexRiscv off the BRAM column.
