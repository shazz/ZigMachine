#!/usr/bin/env python3
"""latency_sim.py: Latency, stall, and underrun margin simulation for ZigMachine FPGA.

Models:
1. CPU Store Path: Blocking stores (posted=0) vs Posted Store Buffer (depth 4, 8, 16) under unloaded/loaded DDR.
2. CPU Sequencer Stall: Polling overhead in vseq.c across 280 lines and 1-4 planes.
3. Video Scanout Underrun Margin: Time-budget vs DDR contention latency for 400-beat row fetch into ping-pong line buffers.
"""

from __future__ import annotations
import argparse
import json
from dataclasses import asdict, dataclass
from typing import Dict, List


@dataclass
class StoreLatencyResult:
    config: str
    stores_per_frame: int
    store_stall_cycles: int
    stall_time_ms: float
    frame_budget_pct_at_100mhz: float
    effective_fps_cap: float


@dataclass
class SequencerStallResult:
    planes: int
    lines: int
    comp_cycles_per_line: int
    total_comp_cycles: int
    sys_wait_cycles_at_100mhz: int
    wait_time_ms: float
    frame_budget_pct_at_100mhz: float


@dataclass
class ScanoutMarginResult:
    ddr_state: str
    line_period_us: float
    fetch_latency_us: float
    slack_us: float
    margin_pct: float
    status: str


def simulate_store_latency(stores: int = 125_000) -> List[StoreLatencyResult]:
    """Evaluates CPU store stalls across configurations for 125k stores (union_beatdis)."""
    configs = [
        ("Blocking Store (Unloaded DDR, lat=24)", 24, 1.0),
        ("Blocking Store (Loaded DDR, lat=62)", 62, 1.0),
        ("Blocking Store (Saturated DDR, lat=120)", 120, 1.0),
        ("Posted Store Buffer 4-entry (drain=2)", 0, 0.08),  # 8% spill
        ("Posted Store Buffer 8-entry (drain=2)", 0, 0.005), # 0.5% spill
        ("Posted Store Buffer 16-entry (drain=2)", 0, 0.0),  # 0% spill
    ]

    results = []
    frame_cycles_100m = 1_666_667  # 100 MHz / 60 fps

    for name, lat, spill_rate in configs:
        if lat > 0:
            stall_cycles = stores * lat
        else:
            # Spill cycles when buffer is temporarily full
            stall_cycles = int(stores * spill_rate * 8)

        stall_ms = (stall_cycles / 100_000_000) * 1000.0
        pct = (stall_cycles / frame_cycles_100m) * 100.0
        # If CPU does 500k ALU instructions + stalls, max achievable FPS:
        work_cycles = 600_000
        fps_cap = 100_000_000 / (work_cycles + stall_cycles)

        results.append(StoreLatencyResult(
            config=name,
            stores_per_frame=stores,
            store_stall_cycles=stall_cycles,
            stall_time_ms=round(stall_ms, 2),
            frame_budget_pct_at_100mhz=round(pct, 1),
            effective_fps_cap=round(fps_cap, 1),
        ))

    return results


def simulate_sequencer_stalls() -> List[SequencerStallResult]:
    """Calculates CPU idle time waiting for compositor passes in vseq.c."""
    # At 125 MHz comp clock vs 100 MHz sys clock:
    # 1 comp cycle = 0.8 sys cycles
    # Pass breakdown:
    # 1. Row Load: 400 beats (PFB) + 400 beats (Pic) = 800 cycles
    # 2. Paint: 400 cycles
    # 3. Mix: 400 cycles
    # 4. Row Store: 400 beats (PFB) + 400 beats (Pic) = 800 cycles
    # Total comp cycles per line: ~1000 (1 plane) to ~2400 (heavy plane)
    planes_cases = [
        (1, 1000),
        (2, 1600),
        (3, 2100),
        (4, 2600),
    ]

    results = []
    frame_cycles_100m = 1_666_667

    for num_p, cyc_per_line in planes_cases:
        total_comp = num_p * 280 * cyc_per_line
        # Sys wait cycles (CPU spins in wait_bits(READY) & wait_bits(PAINTED))
        sys_wait = int(total_comp * (100.0 / 125.0))
        wait_ms = (sys_wait / 100_000_000) * 1000.0
        pct = (sys_wait / frame_cycles_100m) * 100.0

        results.append(SequencerStallResult(
            planes=num_p,
            lines=280 * num_p,
            comp_cycles_per_line=cyc_per_line,
            total_comp_cycles=total_comp,
            sys_wait_cycles_at_100mhz=sys_wait,
            wait_time_ms=round(wait_ms, 2),
            frame_budget_pct_at_100mhz=round(pct, 1),
        ))

    return results


def simulate_scanout_margins() -> List[ScanoutMarginResult]:
    """Calculates video scanout fetch time vs line deadline (26.4 us)."""
    # 800x600@60Hz line period = 1056 * 25.0 ns = 26.4 us
    line_period_us = 26.4
    beats = 400  # 64-bit beats (3200 bytes)
    # Burst size = 16 beats -> 25 bursts per line
    bursts = 25

    # Burst timing model:
    # T_burst = Latency + 16 cycles transfer + Arbitration queue delay
    states = [
        ("Idle DDR (no contention)", 24, 0),
        ("Moderate Load (CPU + 1 plane)", 40, 15),
        ("Heavy Load (CPU + 3 planes + Blitter)", 62, 35),
        ("Extreme Contention (Saturated DDR)", 110, 60),
    ]

    results = []

    for name, lat, arb in states:
        total_cycles_per_burst = lat + 16 + arb
        total_sys_cycles = bursts * total_cycles_per_burst
        fetch_time_us = (total_sys_cycles / 100_000_000) * 1e6  # 100 MHz sys clock
        slack = line_period_us - fetch_time_us
        margin = (slack / line_period_us) * 100.0
        status = "PASS (Safe)" if slack > 5.0 else ("WARNING (Tight)" if slack > 0 else "FAIL (Underrun!)")

        results.append(ScanoutMarginResult(
            ddr_state=name,
            line_period_us=line_period_us,
            fetch_latency_us=round(fetch_time_us, 2),
            slack_us=round(slack, 2),
            margin_pct=round(margin, 1),
            status=status,
        ))

    return results


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--json", help="Path to write JSON summary output")
    args = p.parse_args()

    stores_res = simulate_store_latency(125_000)
    seq_res = simulate_sequencer_stalls()
    scan_res = simulate_scanout_margins()

    print("=" * 88)
    print("1. CPU STORE PATH BOTTLENECK (125k stores/frame, union_beatdis)")
    print("=" * 88)
    print(f"{'Configuration':<42} | {'Stall Ms':<9} | {'% Frame':<8} | {'Max FPS':<8}")
    print("-" * 88)
    for s in stores_res:
        print(f"{s.config:<42} | {s.stall_time_ms:>7.2f}ms | {s.frame_budget_pct_at_100mhz:>6.1f}% | {s.effective_fps_cap:>6.1f}")

    print("\n" + "=" * 88)
    print("2. SEQUENCER POLLING BOTTLENECK (vseq.c polling wait_bits(READY/PAINTED))")
    print("=" * 88)
    print(f"{'Planes':<8} | {'Comp Cycles':<12} | {'Sys Wait Cycles':<16} | {'Wait Ms':<9} | {'% Frame':<8}")
    print("-" * 88)
    for q in seq_res:
        print(f"{q.planes:<8} | {q.total_comp_cycles:>12,} | {q.sys_wait_cycles_at_100mhz:>16,} | {q.wait_time_ms:>7.2f}ms | {q.frame_budget_pct_at_100mhz:>6.1f}%")

    print("\n" + "=" * 88)
    print("3. VIDEO SCANOUT UNDERRUN MARGIN (26.4 us deadline for 400-beat line fetch)")
    print("=" * 88)
    print(f"{'DDR Contention State':<42} | {'Fetch Us':<9} | {'Slack Us':<9} | {'Status':<16}")
    print("-" * 88)
    for m in scan_res:
        print(f"{m.ddr_state:<42} | {m.fetch_latency_us:>7.2f}us | {m.slack_us:>7.2f}us | {m.status:<16}")
    print("=" * 88)

    if args.json:
        data = {
            "store_latency": [asdict(x) for x in stores_res],
            "sequencer_stalls": [asdict(x) for x in seq_res],
            "scanout_margins": [asdict(x) for x in scan_res],
        }
        with open(args.json, "w") as f:
            json.dump(data, f, indent=2)
        print(f"\nWrote latency summary to {args.json}")


if __name__ == "__main__":
    main()
