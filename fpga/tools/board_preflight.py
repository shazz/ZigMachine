"""Prove the board healthy before any SoC test: hp-test bitstream, then a raw write burst with a
CHECK readback on HP0 and HP1, then a ZMVideoAXI row write on HP1. Automates MORNING.md step 1.

    sg dialout -c "uv run --with pyserial python fpga/tools/board_preflight.py"

Exit 0 when both ports pass. A port stuck busy with 0 beats is a wedged AFI that survives PL
reloads: only RST KEY clears it. DO NOT run while another session uses the board.
"""

from __future__ import annotations

import argparse
import sys
import time
from dataclasses import dataclass, field

import uboot_serial as us
from uboot_serial import UBoot, UBootError

BIT = "fpga/build/hp_test/gateware/zm_hp_test.bit"
BANK = {0: 0x43C00100, 1: 0x43C00200}
DST = {0: 0x05000000, 1: 0x05100000}
SEED = {0: 0x10000000, 1: 0x20000000}
BEATS = 0x40  # 4 bursts of 16 x 4 bytes
ROW_BEATS = 0x190
ROW_ADDR = 0x05F01100


@dataclass
class PortResult:
    port: int
    ok: bool = False
    notes: list[str] = field(default_factory=list)


def run_and_wait(con: UBoot, base: int, ctrl: int, wait: float = 2.0) -> tuple[int, int, int]:
    """Start a run; (STATUS, BEATS, ERRS) once idle. Still busy at `wait`: the last values read."""
    con.mw(base, ctrl)
    end = time.monotonic() + wait
    while True:
        status, beats, errs = con.md(base + 0x20, 3)
        if not status & 1 or time.monotonic() > end:
            return status, beats, errs
        time.sleep(0.1)


def check_burst(con: UBoot, n: int, r: PortResult) -> bool:
    base, dst, seed = BANK[n], DST[n], SEED[n]
    con.mw(dst, 0xEEEEEEEE, 0x100)
    for off, val in ((4, dst), (8, 0xF), (0xC, 2), (0x10, 0), (0x14, 4), (0x18, 0xF), (0x1C, seed)):
        con.mw(base + off, val)
    status, beats, errs = run_and_wait(con, base, 3)
    r.notes.append(f"write STATUS={status:#x} BEATS={beats:#x} ERRS={errs}")
    if status & 1 and beats == 0:
        r.notes.append(f"HP{n} WEDGED: press RST KEY")
        return False
    words = con.md(dst, 8)
    r.notes.append("DDR " + " ".join(f"{w:08x}" for w in words))
    if status != 2 or beats != BEATS or errs or words != [seed + i * 2 for i in range(8)]:
        return False
    # [LANE: the 4-byte read beats on a 64-bit channel return odd words in the upper lane]
    status, beats, errs = run_and_wait(con, base, 0x25)
    r.notes.append(f"CHECK STATUS={status:#x} BEATS={beats:#x} ERRS={errs}")
    return status == 2 and not errs


def check_row(con: UBoot, r: PortResult) -> bool:
    base = BANK[1]
    con.mw(base + 0x14, ROW_BEATS)
    con.mw(base + 4, ROW_ADDR)
    status, beats, _ = run_and_wait(con, base, 0xB)
    r.notes.append(
        f"ZMVideoAXI row STATUS={status:#x} BEATS={beats:#x}, DDR " + " ".join(f"{w:08x}" for w in con.md(ROW_ADDR, 4))
    )
    return status == 2 and beats == ROW_BEATS


def preflight(con: UBoot, bit: str = BIT) -> list[PortResult]:
    con.interrupt()
    us.quiesce(con)
    us.load_pl(bit)
    con.cmd("dcache off")
    us.set_afi(con)
    ident = con.md(0x43C00000, 1)[0]
    if ident != us.ID_HPTEST:
        raise UBootError(f"hp-test ID {ident:#x}, want {us.ID_HPTEST:#x}: wrong bitstream loaded?")
    results = []
    for n in (0, 1):
        r = PortResult(n)
        r.ok = check_burst(con, n, r) and (n == 0 or check_row(con, r))
        results.append(r)
    return results


def report(results: list[PortResult]) -> int:
    for r in results:
        print(f"HP{r.port}: {'PASS' if r.ok else 'FAIL'}")
        for line in r.notes:
            print(f"    {line}")
    return 0 if all(r.ok for r in results) else 1


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--bit", default=BIT)
    ap.add_argument("--tty")
    a = ap.parse_args()
    try:
        return report(preflight(UBoot(a.tty), a.bit))
    except UBootError as e:
        print(f"board_preflight: {e}")
        return 2


if __name__ == "__main__":
    sys.exit(main())
