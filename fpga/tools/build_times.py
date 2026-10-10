#!/usr/bin/env python3
"""build_times.py DIR [--label L] [--log build/build_times.txt]: where a bitstream build's time went.

Every openXC7 build (soc/openxc7.py for LiteX SoCs, tools/openxc7.sh `bit` for the small
tops) records each stage's wall time in DIR/stages.txt ("name start end", bash
$EPOCHREALTIME), and nextpnr writes DIR/pnr.log. This prints the table and appends one
line to the log: the stages, nextpnr's own split (HeAP, refinement, router), the fmax of
every clock and how many cells a REUSE build pinned. Stdlib only: openxc7.sh runs it with
the host's python3, outside uv.
"""

from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
LOG = FPGA / "build/build_times.txt"
PNR_SPLIT = {  # nextpnr's own timers (common/place, common/route)
    "heap": r"HeAP Placer Time: ([\d.]+)s",
    "sa": r"SA placement time ([\d.]+)s",
    "refine": r"Placement refine time ([\d.]+)s",
    "router2": r"Router2 time ([\d.]+)s",
    "router1": r"Router1 time ([\d.]+)s",
}
FMAX = re.compile(r"Max frequency for clock\s+'([^']+)': ([\d.]+) MHz")
PINNED = re.compile(r"Pre-placed: (\d+) cell\(s\) pinned to their reference bel")


def read_stages(path: Path) -> dict[str, float]:
    """stage -> seconds; a stage run twice (a retry) adds up."""
    out: dict[str, float] = {}
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        parts = line.split()
        if len(parts) == 3:
            out[parts[0]] = out.get(parts[0], 0.0) + float(parts[2]) - float(parts[1])
    return out


def read_pnr(path: Path) -> dict[str, object]:
    """nextpnr's timers, the last (post-route) fmax of each clock, the REUSE counts."""
    text = path.read_text(errors="replace") if path.exists() else ""
    split = {k: float(m[-1]) for k, rx in PNR_SPLIT.items() if (m := re.findall(rx, text))}
    fmax: dict[str, float] = {}
    for clock, mhz in FMAX.findall(text):
        fmax[clock] = float(mhz)  # later lines (after routing) replace the placer's estimate
    pinned = PINNED.findall(text)
    return {
        "split": split,
        "fmax": fmax,
        "pinned": pinned[-1] if pinned else "",
    }


def summary(stages: dict[str, float], pnr: dict[str, object]) -> tuple[list[str], str]:
    """The printed table and the one-line record."""
    split: dict[str, float] = pnr["split"]  # type: ignore[assignment]  # read_pnr's own dict
    place = split.get("heap", 0.0) + split.get("sa", 0.0) + split.get("refine", 0.0)
    route = split.get("router2", 0.0) + split.get("router1", 0.0)
    total = sum(stages.values())
    rows = [f"  {name:<8}{secs:8.1f} s" for name, secs in stages.items()]
    if "pnr" in stages and (place or route):
        rows.append(
            f"    place {place:6.1f} s (HeAP {split.get('heap', 0.0):.1f} + refine "
            f"{split.get('sa', 0.0) + split.get('refine', 0.0):.1f}), route {route:.1f} s, "
            f"rest {stages['pnr'] - place - route:.1f} s (load, pack, delay matrix, timing, writes)"
        )
    rows.append(f"  {'total':<8}{total:8.1f} s")
    fmax: dict[str, float] = pnr["fmax"]  # type: ignore[assignment]  # read_pnr's own dict
    if fmax:
        rows.append("  fmax    " + ", ".join(f"{c} {f:.2f}" for c, f in fmax.items()))
    if pnr["pinned"]:
        rows.append(f"  reuse   {pnr['pinned']} cells pinned to the base's bels")
    fields = [f"{k}={v:.1f}" for k, v in stages.items()] + [
        f"place={place:.1f}",
        f"route={route:.1f}",
        f"total={total:.1f}",
    ]
    fields.append("fmax=" + ",".join(f"{c}:{f:.2f}" for c, f in fmax.items()))
    if pnr["pinned"]:
        fields.append(f"pinned={pnr['pinned']}")
    return rows, " ".join(fields)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("dir", type=Path, help="the build directory (stages.txt, pnr.log)")
    ap.add_argument("--label", default="", help="what was built (top, seed, REUSE)")
    ap.add_argument("--log", type=Path, default=LOG, help="the file the one-line record is appended to")
    a = ap.parse_args()
    stages = read_stages(a.dir / "stages.txt")
    if not stages:
        print(f"build_times: no {a.dir / 'stages.txt'}", file=sys.stderr)
        return 1
    rows, record = summary(stages, read_pnr(a.dir / "pnr.log"))
    print(f"build times: {a.dir} {a.label}".rstrip())
    print("\n".join(rows))
    a.log.parent.mkdir(parents=True, exist_ok=True)
    with a.log.open("a") as f:
        f.write(f"{time.strftime('%Y-%m-%dT%H:%M:%S')} {a.label or a.dir.name} dir={a.dir} {record}\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
