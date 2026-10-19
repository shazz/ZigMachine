# DDR3 & AXI HP Bandwidth Model Tool (`bandwidth_model.py`)

## Overview

[`bandwidth_model.py`](file:///home/matt/projects/ZigMachine/fpga/review/tools/bandwidth_model.py) is an analytical and workload-driven DDR3 memory bandwidth simulation tool designed for the ZigMachine FPGA architecture on the Xilinx Zynq-7000 (`XC7Z010-1CLG400`).

It quantifies the exact bandwidth and AXI transaction profiles across all four 64-bit High-Performance (HP) ports on the Zynq Processing System (PS) interface.

---

## What It Measures

1. **HP0 — Cart VexRiscv CPU Subsystem:**
   - **Instruction Cache Miss Traffic:** Refill bursts of 32 bytes ($4 \times 64\text{-bit beats}$) based on cart-specific instruction working set sizes.
   - **Data Cache Miss Traffic:** Refill bursts of 32 bytes ($4 \times 64\text{-bit beats}$) for read misses.
   - **Data Cache Write-Through Traffic:** Unbuffered or buffered single-beat 32-bit stores ($4\text{ bytes each}$, `WR32` mode on `WDATA[31:0]`).
   - Comparison between direct-mapped 4 KiB I-cache thrashing vs 16 KiB 2-way set-associative I-cache.

2. **HP1 — Video DMA Subsystem (Compositor & Scanout):**
   - **Scanout Display Fetch:** Fixed real-time scanout of 800 physical pixels $\times$ 280 lines $\times$ 4 bytes ($3,200\text{ bytes/line} = 400\text{ beats}$) at 60 Hz = **$53.76\text{ MB/s}$**.
   - **Compositor Row I/O:** Transfers of Physical Framebuffer (PFB) rows ($3,200\text{ bytes}$) and Picture rows ($3,200\text{ bytes}$) per raster line per plane.
   - **Plane Source (LFB) Fetches:** 320 to 400 bytes per active plane row.
   - Total bandwidth scaling across 1, 2, 3, and 4 active planes.

3. **HP2 — Hardware Blitter Subsystem:**
   - **Multi-Channel Pixel Access:** Up to 3 read sources (A, B, C) and 1 destination write (D) per pixel.
   - **Word-Reuse Coalescing:** Models the 4-pixels-per-word reuse in [`zm_blit_px.v`](file:///home/matt/projects/ZigMachine/fpga/rtl/blitter/zm_blit_px.v).
   - **Single-Beat AXI Command Rate:** Counts individual `ARLEN=0` (64-bit) and `AWLEN=0` (32-bit) transactions per frame to quantify command queue pressure on the PS interconnect.

4. **HP3 — Sound CPU (BARD) & Audio Core Subsystem:**
   - **PCM Stream:** Stereo 16-bit 48 kHz streaming ($192\text{ KB/s}$).
   - **Musashi 68000 Emulation Traffic:** ~330,000 stores and ~50,000 I$ refills per frame for SNDH playback (e.g., Beat Dis).

5. **Physical DDR3-1066 Bus Utilization:**
   - Measures total sustained throughput against the theoretical ceiling:
     $$\text{Peak Bandwidth} = 1066.667\text{ MT/s} \times 2\text{ bytes (16-bit)} = \mathbf{2,133.33\text{ MB/s}}$$
   - Flags when aggregate traffic approaches or exceeds realistic usable bandwidth ($65\text{--}75\%$ of theoretical peak due to refresh, bank conflicts, and turnaround bubbles).

---

## CLI Usage

```sh
# Run bandwidth model and print summary table for all known demoscene carts
python3 fpga/review/tools/bandwidth_model.py

# Export full structured JSON dataset
python3 fpga/review/tools/bandwidth_model.py --json fpga/review/reports/bandwidth_summary.json

# Drill down into detailed per-port metrics for a specific cart
python3 fpga/review/tools/bandwidth_model.py --cart union_beatdis
```

---

## Output Metrics & Evidence

The tool produces:
- `read_mb_frame` / `write_mb_frame`: Megabytes per frame for each HP master.
- `read_mb_s` / `write_mb_s`: Megabytes per second at 60 Hz.
- `total_mb_s`: Aggregate bandwidth consumed by each port.
- `read_tx_per_frame` / `write_tx_per_frame`: Number of discrete AXI transactions per frame.
- `avg_read_burst_bytes` / `avg_write_burst_bytes`: Burst length efficiency.
- `ddr_utilization_pct`: Percentage of DDR3-1066 physical bus capacity consumed.
