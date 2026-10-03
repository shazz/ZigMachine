"""Turn build/mempath/uart/<core>/<mem>/<variant>/<cart>.txt into
build/mempath/report.txt and the three tables of CYCLES.md "Memory path"
(between their markers).

    uv run python tools/mempath_report.py

MHz = the cart's p95 frame (frames after the first 5) x 60 / 1e6, as in the
cycles table. A cell is `-` until its run has landed, and carries a `!` if the
run's hashes differ from scene_hash.mjs's or the native host's.
"""

from __future__ import annotations

import re
from pathlib import Path
from statistics import mean

from cycles_parse import Run, parse
from cycles_report import p95, series, steady, verify
from mempath_cfg import CARTS, CORES, MEM, PRED_CORES
from util import group_cells

FPGA = Path(__file__).resolve().parent.parent
OUT = FPGA / "build/mempath"
UTIL = FPGA / "build/util"
Runs = dict[tuple[str, str, str, str], Run]


def load() -> Runs:
    runs: Runs = {}
    for log in sorted((OUT / "uart").glob("*/*/*/*.txt")):
        variant, mem, core = log.parent.name, log.parent.parent.name, log.parent.parent.parent.name
        run = parse(log)
        if run.frames and run.end is not None:
            runs[(core, mem, variant, log.stem)] = run
    return runs


def mhz(runs: Runs, key: tuple[str, str, str, str]) -> str:
    run = runs.get(key)
    if run is None:
        return "-"
    flag = "" if verify(key[3], run) == "ok" else "!"
    return f"{(p95(steady(series(run, 'cart'))) or 0) * 60 / 1e6:.0f}{flag}"


def memory_table(runs: Runs) -> list[list[str]]:
    mems = [m for m in MEM if any(k[1] == m for k in runs)]
    head = ["cart", "build", *mems]
    rows = [
        [tag, variant, *[mhz(runs, ("std", m, variant, tag)) for m in mems]]
        for variant in ("aligned", "nobounds")
        for tag in CARTS
        if any(k[2:] == (variant, tag) for k in runs)
    ]
    return [head, *rows]


def util_of(core: str) -> tuple[str, str]:
    """LUT and BRAM of the core, from tools/util.py's last synthesis of it."""
    stat = UTIL / ("vexriscv_std.txt" if core == "std" else f"vex_{core}.txt")
    if not stat.exists():
        return "-", "-"
    text = stat.read_text()
    ramb = {k: sum(int(n) for n in re.findall(rf"^\s+(\d+)\s+RAMB{k}E1\s*$", text, re.MULTILINE)) for k in (18, 36)}
    return str(group_cells(text)["LUT"]), f"{ramb[36] + ramb[18] / 2:g}"


def refills(runs: Runs, core: str, tag: str) -> str:
    """I$ line refills per steady frame (8 words a line)."""
    run = runs.get((core, "hp_wc", "aligned", tag))
    return "-" if run is None else f"{mean(steady(series(run, 'cart', 'ibus_ack'))) / 8e3:.0f}k"


def cache_table(runs: Runs) -> list[list[str]]:
    carts = ["skystrike", "polkadots"]  # mempath_cfg PLANS["caches"]
    head = ["core", "LUT", "BRAM (36 Kb)", *carts, "polkadots I$ refills/frame"]
    rows = [[c, *util_of(c), *[mhz(runs, (c, "hp_wc", "aligned", t)) for t in carts], refills(runs, c, "polkadots")]
            for c in CORES]  # fmt: skip
    return [head, *rows]


def prediction_table(runs: Runs) -> list[list[str]]:
    """MHz per cart on each branch-predictor core, and the change against the first."""
    head = ["core", *CARTS, "cycles vs static"]
    base = [runs.get((PRED_CORES[0], "hp_wc", "aligned", t)) for t in CARTS]
    rows = []
    for core in PRED_CORES:
        cells = [mhz(runs, (core, "hp_wc", "aligned", t)) for t in CARTS]
        cur = [runs.get((core, "hp_wc", "aligned", t)) for t in CARTS]
        pairs = [(p95(steady(series(b, "cart"))), p95(steady(series(c, "cart")))) for b, c in zip(base, cur) if b and c]
        delta = "-" if not pairs else " / ".join(f"{100 * (c / b - 1):+.1f} %" for b, c in pairs if b)
        rows.append([core, *cells, delta])
    return [head, *rows]


def text(table: list[list[str]]) -> list[str]:
    widths = [max(len(x) for x in col) for col in zip(*table, strict=False)]
    return ["  ".join(x.ljust(w) for x, w in zip(r, widths, strict=False)) for r in table]


def markdown(table: list[list[str]]) -> str:
    out = ["| " + " | ".join(table[0]) + " |", "|" + "---|" * len(table[0])]
    return "\n".join(out + ["| " + " | ".join(r) + " |" for r in table[1:]])


def splice(md: str, name: str, table: list[list[str]]) -> str:
    begin, end = f"<!-- mempath-{name}:begin -->", f"<!-- mempath-{name}:end -->"
    if begin not in md:
        return md
    head, rest = md.split(begin, 1)
    return head + begin + "\n" + markdown(table) + "\n" + end + rest.split(end, 1)[1]


def main() -> None:
    runs = load()
    tables = {"memory": memory_table(runs), "caches": cache_table(runs), "prediction": prediction_table(runs)}
    lines = []
    for name, table in tables.items():
        lines += [f"== {name} (MHz for 60 fps, p95 frame)", *text(table), ""]
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "report.txt").write_text("\n".join(lines))
    print("\n".join(lines))
    md_path = FPGA / "CYCLES.md"
    md = md_path.read_text()
    for name, table in tables.items():
        md = splice(md, name, table)
    md_path.write_text(md)


if __name__ == "__main__":
    main()
