# Latency, Stall & Scanout Underrun Simulator (`latency_sim.py`)

## Overview

[`latency_sim.py`](file:///home/matt/projects/ZigMachine/fpga/review/tools/latency_sim.py) is a cycle-accurate latency and timing margin simulator for the ZigMachine FPGA. It models the latency pipelines, pipeline stalls, and real-time deadline margins that limit frame rate and cause visual glitching.

---

## What It Measures

1. **CPU Store Path Stall Cycles:**
   - **Blocking Store Mode (`posted=0`):** Calculates CPU wait cycles when each store must wait for the AXI write response (`BVALID & BREADY`) from the DDR controller ($24\text{ cycles}$ unloaded, $62\text{ cycles}$ loaded, $120\text{ cycles}$ saturated).
   - **Posted Store Buffer (`posted=4, 8, 16`):** Models buffer absorption rate and drain frequency ($2\text{ cycles/store}$) to measure buffer full / spill stalls.
   - **Frame Budget Consumption:** Measures stall cycles against the $100\text{ MHz}$ frame budget ($1,666,667\text{ cycles}$ at $60\text{ fps}$) and computes the maximum theoretical FPS cap.

2. **Sequencer Polling Drag (`vseq.c`):**
   - **Status Register Polling Overhead:** Models the CPU busy-waiting on `READY`, `DRAINED`, and `PAINTED` bits via Wishbone CSR reads over the CSR bridge.
   - **Pass Execution Clocks:** Simulates compositor row I/O (load PFB, load Pic, paint, mix, store PFB, store Pic) running at $125\text{ MHz}$ `comp_clk` against $100\text{ MHz}$ `sys_clk`.
   - **Scaling Across Planes:** Measures total CPU wait time across 1, 2, 3, and 4 planes over 280 raster lines.

3. **Video Scanout Display Buffer Underrun Margin:**
   - **Real-Time Scanline Deadline:** 800x600@60Hz timing has a line period of $1,056\text{ pixels} \times 25.0\text{ ns} = \mathbf{26.4\ \mu\text{s}}$ ($2,640\text{ sys cycles}$ at $100\text{ MHz}$).
   - **Ping-Pong Buffer Constraint:** [`zm_video_dcram.v`](file:///home/matt/projects/ZigMachine/fpga/rtl/video/zm_video_dcram.v) holds only two line buffers. While buffer 0 is scanned out, buffer 1 must load $400\text{ beats}$ ($25\text{ bursts of 16 beats}$) from DDR.
   - **Contention Latency & Slack:** Evaluates fetch latency and slack margin ($\text{Deadline} - \text{Fetch Time}$) under idle DDR, moderate load, heavy load (Compositor + Blitter + CPU), and saturated DDR. Flags `PASS`, `WARNING (Tight)`, or `FAIL (Underrun!)`.

---

## CLI Usage

```sh
# Run latency simulator and display summary tables
python3 fpga/review/tools/latency_sim.py

# Export full structured JSON dataset
python3 fpga/review/tools/latency_sim.py --json fpga/review/reports/latency_summary.json
```

---

## Output Metrics & Evidence

The tool produces:
- `store_stall_cycles` / `stall_time_ms`: Total CPU stall time per frame due to writes.
- `frame_budget_pct_at_100mhz`: Fraction of the $60\text{ fps}$ cycle budget consumed by stalls.
- `effective_fps_cap`: Upper ceiling on frame rate imposed solely by store latency.
- `sys_wait_cycles_at_100mhz` / `wait_time_ms`: CPU cycles lost polling the compositor.
- `fetch_latency_us` / `slack_us`: Video scanout fetch duration vs line period.
- `margin_pct` / `status`: Real-time safety margin against video underrun glitching.
