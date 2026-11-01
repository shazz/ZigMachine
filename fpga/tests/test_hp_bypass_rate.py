"""What the read bypass buys a memcpy (soc/zm_hp_bypass.py): each 32-byte line is a refill of the
source then eight word stores to the destination. Without the bypass the next refill waits for
those eight stores to drain (BENCH_REPORTS.md 2026-10-18: mc.lib 2.73 c/B, "reads still wait");
with it the refill goes out at once and the stores drain under it. The model port
(tests/hp_port_model.py) answers a write in B_LAT and a refill in about the board's 48 cycles."""

from __future__ import annotations

from hp_port_model import PortBench, Seen, Sim, port
from migen import run_simulation
from test_hp_bypass import refill
from test_hp_posted import access

from soc.zm_hp import CPU_BASE

SRC, DST, LINES = CPU_BASE + 0x10000, CPU_BASE + 0x20000, 16


def memcpy_cycles_per_byte(read_bypass: bool) -> float:
    p, out = PortBench(read_bypass), {}

    def cpu() -> Sim:
        t = 0
        for n in range(LINES):
            _, c = yield from refill(p, SRC + 32 * n)
            t += c
            for i in range(8):
                _, c = yield from access(p, DST + 32 * n + 4 * i, i)  # type: ignore[arg-type]
                t += c + 1  # access() spends one more cycle dropping cyc
        out["t"] = t

    run_simulation(p, [cpu(), port(p, LINES * 200, Seen())])
    return out["t"] / (32 * LINES)


def test_a_memcpy_line_no_longer_waits_for_the_previous_line_stores() -> None:
    drain, bypass = memcpy_cycles_per_byte(False), memcpy_cycles_per_byte(True)
    print(f"memcpy model: {drain:.2f} c/B drained, {bypass:.2f} c/B with the bypass")
    assert bypass <= 0.85 * drain, (drain, bypass)
