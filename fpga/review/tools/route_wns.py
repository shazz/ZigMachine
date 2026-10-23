#!/usr/bin/env python3
"""Emit the whole per-clock WNS/TNS/WHS table from a report_timing_summary file.

    python3 review/tools/route_wns.py /tmp/opencode/rev/pletdir/timing_route.rpt [out.md]

Companion to ooc_collect.py for the FULL SoC: several clocks per Intra Clock Table, blank
cells when a domain has no critical path. Columns are sliced from the header's text starts,
so blank cells cannot shift tokens. Indented rows are child (generated) clocks of the row
above; kept, shown with the indentation.
"""
import sys
from pathlib import Path


COLS = ["Clock", "WNS(ns)", "TNS(ns)", "TNS Failing Endpoints", "TNS Total Endpoints",
        "WHS(ns)", "THS(ns)", "THS Failing Endpoints", "THS Total Endpoints", "WPWS(ns)"]


def spans(header: str, tokens: list[str]) -> dict[str, tuple[int, int]]:
    found = sorted((header.find(t), t) for t in tokens if header.find(t) >= 0)
    out = {}
    for i, (s, t) in enumerate(found):
        e = found[i + 1][0] if i + 1 < len(found) else len(header)
        out[t] = (s, e - s)
    return out


def cell(row: str, w: tuple[int, int]) -> str:
    return row[w[0]:w[0] + w[1]].strip() if len(row) > w[0] else ""


def is_rule(row: str) -> bool:
    s = row.strip()
    return bool(s) and s.replace("-", "").replace("=", "").strip() == ""


def _num(text: str) -> float | None:
    try:
        return float(text)
    except ValueError:
        return None


def parse(txt: list[str]) -> tuple[list[tuple[str, dict]], list[tuple[str, dict]]]:
    data, clocks = [], []
    # --- Intra Clock Table (WNS/TNS/WHS per clock domain)
    hi = next((i for i, ln in enumerate(txt) if "Intra Clock Table" in ln), None)
    if hi is not None:
        hj = next((j for j in range(hi, hi + 10)
                   if "WNS(ns)" in txt[j] and "WHS(ns)" in txt[j]), None)
        if hj is not None:
            w = spans(txt[hj], COLS)
            for k in range(hj + 1, len(txt)):
                if "From Clock" in txt[k] or "Path Group" in txt[k] or "Table" in txt[k]:
                    break
                if is_rule(txt[k]) or not txt[k].strip():
                    continue
                name = cell(txt[k], w["Clock"])
                if not name:
                    continue
                data.append((name, {"WNS(ns)": _num(cell(txt[k], w["WNS(ns)"])),
                                    "TNS(ns)": _num(cell(txt[k], w["TNS(ns)"])),
                                    "WHS(ns)": _num(cell(txt[k], w["WHS(ns)"]))}))
    # --- Clock Summary (period / frequency per domain)
    ci = next((i for i, ln in enumerate(txt) if "Clock Summary" in ln and "WNS" not in ln), None)
    if ci is not None:
        cj = next((j for j in range(ci, min(ci + 10, len(txt)))
                   if "Waveform(ns)" in txt[j] and "Period(ns)" in txt[j]), None)
        if cj is not None:
            w = spans(txt[cj], ["Clock", "Waveform(ns)", "Period(ns)", "Frequency(MHz)"])
            seen = False
            for k in range(cj + 1, len(txt)):
                if not txt[k].strip():
                    continue
                s2 = txt[k].strip()
                if is_rule(txt[k]):
                    if seen:          # the rule AFTER the data block closes the table
                        break
                    continue          # the rule under the header is skipped
                if s2.startswith("|"):
                    break
                seen = True
                name = cell(txt[k], w["Clock"])
                if not name or name.startswith("-"):
                    continue
                clocks.append((name, {"Period(ns)": cell(txt[k], w["Period(ns)"]),
                                      "Frequency(MHz)": cell(txt[k], w["Frequency(MHz)"])}))
                if len(clocks) >= 24:
                    break
    return data, clocks


def main() -> int:
    path = Path(sys.argv[1])
    md = Path(sys.argv[2]) if len(sys.argv) > 2 else None
    data, clocks = parse(path.read_text().splitlines())
    if not data:
        sys.exit(f"route_wns: no Intra Clock rows parsed from {path}")
    def fmt(v):
        return f"{v:7.3f}" if v is not None else "      - "
    out = ["# Post-route per-clock timing: " + str(path), "",
           "| clock | WNS (ns) | TNS (ns) | WHS (ns) |", "|---|---|---|---|"]
    for name, r in data:
        out.append(f"| {name} | {fmt(r['WNS(ns)'])} | {fmt(r['TNS(ns)'])} | {fmt(r['WHS(ns)'])} |")
    if clocks:
        out += ["", "## Clock Summary", "", "| clock | period (ns) | Freq (MHz) |",
                "|---|---|---|"]
        for name, c in clocks:
            out.append(f"| {name} | {c['Period(ns)']} | {c['Frequency(MHz)']} |")
    text = "\n".join(out) + "\n"
    print(text)
    if md:
        md.write_text(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
