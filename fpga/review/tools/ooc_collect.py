#!/usr/bin/env python3
"""Aggregate the chain's OOC sweep results into one markdown + CSV table.

    python3 review/tools/ooc_collect.py [<ooc_dir>] [> out.md]

Scans <ooc_dir>/<top>_<period>in_ns/ (default /tmp/opencode/rev/ooc) for
timing_summary.rpt + util.rpt pairs and extracts per block/period:
  LUT, FF, RAMB36 tiles, DSPs  (from util.rpt)
  WNS, TNS, WHS                (from timing_summary.rpt "Intra Clock Table")
  fmax_est = 1000 / (period - WNS)
This is the per-block fmax + finite-resource evidence used in SOC_REVIEW.md F4/F5.
"""
import re
import sys
from pathlib import Path

DEFAULT_DIR = "/tmp/opencode/rev/ooc"


def parse_timing(path: Path) -> dict | None:
    lines = path.read_text().splitlines()
    for i, ln in enumerate(lines):
        if "Intra Clock Table" not in ln:
            continue
        # within the next few lines sits the whitespace-delimited column header
        for j in range(i, min(i + 8, len(lines))):
            if "WNS(ns)" not in lines[j] or "WHS(ns)" not in lines[j]:
                continue
            for ln2 in lines[j + 1:j + 40]:
                t = ln2.split()
                if not t or not t[0][0].isalpha():
                    continue                      # separator rules / blank lines
                try:
                    return {"clk": t[0], "wns": float(t[1]), "tns": float(t[2]),
                            "whs": float(t[5])}
                except (ValueError, IndexError):
                    continue
            break
    return None


def parse_util(path: Path) -> dict:
    vals = {"LUT": None, "FF": None, "RAMB36": None, "DSP": None}
    for ln in path.read_text().splitlines():
        for key, pat in (("LUT", r"\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)"),
                         ("FF", r"\|\s*Slice Registers\s*\|\s*([0-9]+)"),
                         ("RAMB36", r"\|\s*Block RAM Tile\s*\|\s*([0-9.]+)"),
                         ("DSP", r"\|\s*DSPs\s*\|\s*([0-9.]+)")):
            if vals[key] is None:
                m = re.search(pat, ln)
                if m:
                    vals[key] = float(m.group(1))
    return vals


def main() -> int:
    base = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(DEFAULT_DIR)
    rows = []
    for d in sorted(base.iterdir()):
        if not (d / "timing_summary.rpt").exists():
            continue
        m = re.match(r"(.+)_([0-9.]+)ns$", d.name)
        top, period = (m.group(1), float(m.group(2))) if m else (d.name, float("nan"))
        t = parse_timing(d / "timing_summary.rpt") or {}
        u = parse_util(d / "util.rpt")
        wns = t.get("wns")
        fmax = 1000.0 / (period - wns) if wns is not None and period > 0 else None
        rows.append({"top": top, "period": period, **u, **t, "fmax": fmax})
    if not rows:
        sys.exit(f"ooc_collect: no sweep results under {base}")
    print("| block | target (ns) | fmax_est (MHz) | WNS (ns) | TNS (ns) | WHS (ns) |"
          " LUT | FF | RAMB36 | DSP |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for r in rows:
        fm = f"{r['fmax']:7.1f}" if r["fmax"] else "   n/a "
        wns = f"{r['wns']:7.3f}" if r.get("wns") is not None else "  n/a "
        tns = f"{r['tns']:8.3f}" if r.get("tns") is not None else "  n/a "
        whs = f"{r['whs']:7.3f}" if r.get("whs") is not None else "  n/a "
        print(f"| {r['top'][:28]} | {r['period']:5.2f} | {fm} | {wns} | {tns} | {whs} | "
              f"{r['LUT']:7.0f} | {r['FF']:7.0f} | {r['RAMB36']:4.0f} | {r['DSP']:3.0f} |")
    return 0


if __name__ == "__main__":
    sys.exit(main())
