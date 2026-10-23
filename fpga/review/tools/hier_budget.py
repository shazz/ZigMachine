#!/usr/bin/env python3
"""Extract a per-hierarchy resource budget from a Vivado hierarchical utilisation report.

    python3 review/tools/hier_budget.py <report_utilization -hierarchical .rpt> [out.md]

Parses rows of report_utilization -hierarchical (the tool of record for "where does the
SoC spend LUTs / FFs / BRAM / DSP"), groups them by hierarchy depth and prints ranked
tables. XC7Z010 device budget: 17,600 LUT / 35,200 FF / 60 RAMB36-equiv / 80 DSP.
RAMB36-equiv = RAMB36 + RAMB18/2 (two RAMB18 make one RAMB36).
"""
import sys
from pathlib import Path

DEV = {"LUT": 17_600, "FF": 35_200, "BRAM36E": 60, "DSP": 80}


def parse(path: str) -> list[dict]:
    rows: list[dict] = []
    for ln in Path(path).read_text().splitlines():
        if not ln.startswith("|") or "Module" in ln or "-+-" in ln:
            continue
        raw = ln.strip("|").split("|")
        if len(raw) < 10:
            continue
        inst_raw = raw[0]
        depth = (len(inst_raw) - len(inst_raw.lstrip())) // 2  # 1 sep-space + 2 per level
        c = [x.strip() for x in raw]
        try:
            v = [int(x.split()[0]) for x in c[2:10]]
        except ValueError:
            continue
        rows.append({"depth": depth, "inst": c[0].strip(), "mod": c[1],
                     "LUT": v[0], "LogicLUT": v[1], "LUTRAM": v[2], "SRL": v[3],
                     "FF": v[4], "RAMB36": v[5], "RAMB18": v[6], "DSP": v[7]})
    if not rows:
        sys.exit(f"hier_budget: no rows parsed from {path}")
    return rows


def fmt_head():
    return ("| {:<30} | {:>7} | {:>6} | {:>6} | {:>7} | {:>7} | {:>5} | {:>5} | {:>4} |".format(
            "hierarchy", "LUT", "%LUT", "%dev", "LUTRAM", "FF", "RAM36", "RAM18", "DSP"))


def fmt_row(name, r, total_lut):
    return ("| {:<30} | {:>7} | {:>6.1f} | {:>6.1f} | {:>7} | {:>7} | {:>5} | {:>5} | {:>4} |".format(
            name[:30], r["LUT"], 100 * r["LUT"] / max(total_lut, 1),
            100 * r["LUT"] / DEV["LUT"], r["LUTRAM"], r["FF"],
            r["RAMB36"], r["RAMB18"], r["DSP"]))


def main() -> int:
    path = sys.argv[1]
    md = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    rows = parse(path)
    top = rows[0]          # depth 0 = the whole design
    total_lut = top["LUT"]
    equiv = round(top["RAMB36"] + top["RAMB18"] / 2, 1)
    out = [f"# Vivado hierarchical budget: {Path(path).parent.name}", "",
           f"{total_lut} LUT ({100 * total_lut / DEV['LUT']:.1f} % of a 7010), "
           f"{top['FF']} FF ({100 * top['FF'] / DEV['FF']:.1f} %), "
           f"{top['RAMB36']} RAMB36 + {top['RAMB18']} RAMB18 (= {equiv} RAMB36-equiv, "
           f"{100 * equiv / DEV['BRAM36E']:.1f} %), {top['DSP']} DSP "
           f"({100 * top['DSP'] / DEV['DSP']:.1f} %).", "",
           fmt_head(), "|-|---|---|---|---|---|---|---|---|"]
    maxdepth = max(r["depth"] for r in rows)
    for d in range(1, maxdepth + 1):
        sub = [r for r in rows if r["depth"] == d]
        if not sub:
            continue
        out += ["", f"## depth {d}", "", fmt_head(),
                "|-|---|---|---|---|---|---|---|---|"]
        for r in sorted(sub, key=lambda x: -x["LUT"]):
            out.append(fmt_row(r["inst"], r, total_lut))
    txt = "\n".join(out) + "\n"
    print(txt)
    if md:
        md.write_text(txt)
    return 0


if __name__ == "__main__":
    sys.exit(main())
