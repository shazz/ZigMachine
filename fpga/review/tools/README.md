# ZigMachine FPGA Review & Profiling Tools Suite

This directory contains analytical models, cycle-accurate simulators, and Vivado measurement harnesses developed to evaluate the performance, memory bandwidth, latency bottlenecks, and silicon resource budget of the ZigMachine FPGA design on the Xilinx Zynq-7000 (`XC7Z010-1`).

---

## Tool Index

| Tool | Script | Dedicated README | Purpose |
|---|---|---|---|
| **Bandwidth Model** | [`bandwidth_model.py`](bandwidth_model.py) | [bandwidth_model/README.md](bandwidth_model/README.md) | Computes DDR3 and AXI HP port bandwidth, transaction rates, burst sizes, and bus utilization across carts. |
| **Latency Simulator** | [`latency_sim.py`](latency_sim.py) | [latency_sim/README.md](latency_sim/README.md) | Models CPU store stalls, sequencer CSR polling cycles, and video scanout line buffer underrun margins. |
| **Vivado OOC Sweeper** | [`vivado_perf_sweep.py`](vivado_perf_sweep.py) | [vivado_perf_sweep/README.md](vivado_perf_sweep/README.md) | Runs Vivado 2026.1 ML Standard out-of-context synthesis, placement, and routing to extract WNS, Fmax, and critical paths. |
| **Master Suite Runner** | [`run_all_review_tools.sh`](run_all_review_tools.sh) | — | Executes all tools end-to-end and aggregates JSON datasets into `../reports/`. |

---

## Quick Start

```sh
# Run the complete review suite end-to-end
./fpga/review/tools/run_all_review_tools.sh

# Or run individual tools
python3 fpga/review/tools/bandwidth_model.py
python3 fpga/review/tools/latency_sim.py
python3 fpga/review/tools/vivado_perf_sweep.py --candidate zm_blit_px --period 10.0
```

All generated summary datasets are written to [`fpga/review/reports/`](../reports/).
