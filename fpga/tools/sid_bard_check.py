"""The BARD SID study: BARD's uart (tools/sid_bard_run.sh) against the host twin's hashes.

Prints, per tune, the start's cost, the mean of the warm frames (frame 0 dropped) and the peak, in Mc a
60 Hz frame and % of BARD (1.667 Mc), the bus waits and the soft divides; exits 1 if any frame's PCM
hash differs from the host's (tools/sid_bard_host.c), or if BARD rendered no frame at all.
    uv run python tools/sid_bard_check.py <prototypes/sid_re/build/TAG>
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

BUDGET = 1_666_667  # BARD cycles in a 60 Hz frame (scbench.h CB_FRAME_BUDGET)
SID = re.compile(r"^SID (\S+) (\d+) cyc (\d+) rate (\d+) hq (\d) div (\d+) hash ([0-9a-f]{8})")
FW = re.compile(r"^FW (-?\d+) (\d+) (\d+)")
START = re.compile(r"^F -1 (\d+)")


def parse(uart: Path) -> tuple[dict[str, list[tuple[int, int, int, str, int]]], dict[str, int]]:
    """Per tune: (frame, cycles, divides, hash, dbus waits) and the start's cycles."""
    frames: dict[str, list[tuple[int, int, int, str, int]]] = defaultdict(list)
    starts: dict[str, int] = {}
    pending_start = 0
    dbus = 0
    for line in uart.read_text(errors="replace").splitlines():
        if m := START.match(line):
            pending_start = int(m[1])
        elif m := FW.match(line):
            dbus = int(m[3])
        elif m := SID.match(line):
            name = m[1]
            starts.setdefault(name, pending_start)
            frames[name].append((int(m[2]), int(m[3]), int(m[6]), m[7], dbus))
    return frames, starts


def host_hashes(path: Path) -> dict[int, str]:
    out: dict[int, str] = {}
    for line in path.read_text().splitlines():
        if line.startswith("SID "):
            _, f, _, h = line.split()
            out[int(f)] = h
    return out


def main() -> int:
    b = Path(sys.argv[1])
    frames, starts = parse(b / "bard_uart.txt")
    if not frames:
        print("no SID frame in the uart")
        return 1
    bad = 0
    print(f"{'tune':14} {'start Mc':>8} {'mean Mc':>8} {'mean %':>7} {'peak %':>7} {'dbus/fr':>8} {'div/fr':>7} hash")
    for name, rows in frames.items():
        host = host_hashes(b / f"{name}.txt") if (b / f"{name}.txt").exists() else {}
        mism = [f for f, _, _, h, _ in rows if host.get(f) != h]
        bad += len(mism)
        warm = [r for r in rows if r[0] > 0] or rows
        mean = sum(r[1] for r in warm) / len(warm)
        peak = max(r[1] for r in rows)
        dbus = sum(r[4] for r in warm) / len(warm)
        divs = sum(r[2] for r in warm) / len(warm)
        verdict = "exact" if not mism else f"DIFF frames {mism}" if host else "no host"
        print(f"{name:14} {starts[name] / 1e6:8.3f} {mean / 1e6:8.3f} {100 * mean / BUDGET:6.1f}% "
              f"{100 * peak / BUDGET:6.1f}% {dbus / 1e3:7.0f}k {divs:7.0f} {verdict} ({len(rows)} frames)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
