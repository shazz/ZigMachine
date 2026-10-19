#!/usr/bin/env bash
# run_all_review_tools.sh: Execute the complete ZigMachine FPGA review and profiling suite.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REVIEW_DIR="$(dirname "$SCRIPT_DIR")"
REPORT_DIR="$REVIEW_DIR/reports"
mkdir -p "$REPORT_DIR"

echo "================================================================================"
echo "RUNNING ZIGMACHINE FPGA PERFORMANCE & BOTTLENECK REVIEW SUITE"
echo "================================================================================"

echo ""
echo ">>> [1/3] Running DDR3 / AXI HP Bandwidth Model..."
python3 "$SCRIPT_DIR/bandwidth_model.py" --json "$REPORT_DIR/bandwidth_summary.json"

echo ""
echo ">>> [2/3] Running Latency, Stall & Scanout Underrun Simulation..."
python3 "$SCRIPT_DIR/latency_sim.py" --json "$REPORT_DIR/latency_summary.json"

echo ""
echo ">>> [3/3] Running Vivado OOC Timing Sweeps on Critical Modules..."
python3 "$SCRIPT_DIR/vivado_perf_sweep.py" --json "$REPORT_DIR/vivado_sweep.json"

echo ""
echo "================================================================================"
echo "ALL REVIEW TOOLS COMPLETED SUCCESSFULLY."
echo "Reports and data generated in $REPORT_DIR:"
ls -lh "$REPORT_DIR"
echo "================================================================================"
