# Vivado Out-of-Context Performance Sweeper (`vivado_perf_sweep.py`)

## Overview

[`vivado_perf_sweep.py`](file:///home/matt/projects/ZigMachine/fpga/review/tools/vivado_perf_sweep.py) automates the execution of AMD/Xilinx Vivado ML Standard (2026.1 Build 6511674) to perform Out-of-Context (OOC) synthesis, logic optimization, placement, and routing on individual RTL processing blocks of the ZigMachine FPGA.

Target Device: `xc7z010clg400-1` (Zynq-7000 speed grade -1).

---

## What It Measures

1. **Timing Closure & Worst Negative Slack (WNS):**
   - Sweeps target clock periods (e.g. $10.0\text{ ns}$ / $100\text{ MHz}$, $8.0\text{ ns}$ / $125\text{ MHz}$, $6.67\text{ ns}$ / $150\text{ MHz}$).
   - Extracts post-route Worst Negative Slack (WNS) and Total Negative Slack (TNS).
   - Computes empirical achievable $F_{\text{max}} = \frac{1000}{T_{\text{target}} - \text{WNS}}$.

2. **Resource Consumption Breakdown:**
   - Slice LUTs (and LUTRAM / distributed RAM).
   - Slice Registers (Flip-Flops).
   - Block RAM tiles (RAMB36 / RAMB18).
   - DSP48E1 arithmetic slices.

3. **Critical Path & Logic Level Profiling:**
   - Identifies exact source cell, pin, and clock.
   - Identifies exact destination cell, pin, and clock.
   - Measures total data path delay partitioned into **logic delay** vs **routing delay**.
   - Counts logic levels (LUTs, CARRY4s, DSPs, Muxes) along the worst path.

---

## Supported RTL Candidates

- `zm_video_plane`: Plane geometry generator, address calculation (`base + row * stride + hs`), and overscan logic.
- `zm_video_mix`: 2-pixel-per-clock alpha blender using 12 DSP48E1 multipliers.
- `zm_blit_px`: Blitter pixel processing unit, minterm evaluator, and word reuse detector.
- `zm_blit_core`: Full blitter top-level, clipping engine, overlap checker, and sequencers.
- `zm_audio_soc`: Audio subsystem top-level including YM2149 (`jt49`), Paula PCM channels, and mixer.

---

## CLI Usage

```sh
# Run timing sweep on a specific block at a given clock period
python3 fpga/review/tools/vivado_perf_sweep.py --candidate zm_blit_px --period 10.0

# Run sweep across multiple target frequencies and export JSON
python3 fpga/review/tools/vivado_perf_sweep.py --candidate zm_video_plane --json fpga/review/reports/plane_sweep.json

# Run all candidates across their default periods
python3 fpga/review/tools/vivado_perf_sweep.py --json fpga/review/reports/vivado_sweep.json
```

---

## Output Metrics & Evidence

The tool produces:
- `target_period_ns` / `target_freq_mhz`: Target constraint.
- `wns_ns`: Timing slack (positive = MET, negative = VIOLATED).
- `achievable_fmax_mhz`: Maximum frequency supported by the routed netlist.
- `luts`, `ffs`, `bram_tiles`, `dsps`: Actual cell counts on silicon.
- `critical_path_source` $\to$ `critical_path_dest`: Endpoints of the limiting timing path.
- `critical_path_delay_ns` & `logic_levels`: Delay and depth along the critical path.
