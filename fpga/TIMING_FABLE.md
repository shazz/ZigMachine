# Closing timing on the Z7-Lite under openXC7 (Fable, pass 1, 2026-10-02)

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
