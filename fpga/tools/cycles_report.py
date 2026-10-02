"""Turn the cycles-sim logs (build/cycles/uart/<variant>/<tag>.txt) into
build/cycles/report.txt and the table in fpga/CYCLES.md (between its markers).

    uv run python tools/cycles_report.py

Frames 1..WARMUP are reported apart (`first`): a cart's first frames build
tables and decode assets, which a screen does once. Every figure is cycles of
the CART CPU at any clock; MHz for 60 fps is cycles * 60 / 1e6.
"""

from __future__ import annotations

import json
from pathlib import Path
from statistics import mean

from cycles_parse import CLASSES_L, COUNTERS, Run, parse

FPGA = Path(__file__).resolve().parent.parent
CYC = FPGA / "build/cycles"
WARMUP = 5
# Assumed VexRiscv FPU cost per operation, in cycles of a dependent chain
# (CYCLES.md, "FPU estimate"; third_party/VexRiscv README: add/mul/fma pipelined,
# divide radix 4, sqrt radix 2). A class not listed stays soft: F-only has no
# f64, and rv32 has no 64-bit integer <-> float conversion in either extension.
HW_F = {"FADD": 5, "FMUL": 5, "FDIV": 18, "FSQRT": 30, "FCMP": 2, "FCVT": 3, "FROUND": 12, "FNEG": 1}
HW_FD = HW_F | {"FD": 3, "DADD": 6, "DMUL": 7, "DDIV": 32, "DSQRT": 60, "DCMP": 2, "DCVT": 3, "DROUND": 14, "DNEG": 1}
# Assumed extra latency on the board's DDR, per 32-byte cache line refill and
# per write-through store (CYCLES.md, "Sim fidelity").
DDR_LINE, DDR_STORE = 30, 10
MARK_BEGIN, MARK_END = "<!-- cycles-table:begin -->", "<!-- cycles-table:end -->"


def verify(tag: str, run: Run) -> str:
    """'ok' only if the sampled hashes equal scene_hash.mjs's AND the native host's."""
    if run.fatal or run.json is None:
        return "FAIL" if run.fatal else "no-json"
    j = run.json
    for kind in ("js", "native"):
        ref = CYC / "ref" / f"{tag}.{j['frames']}.{j['every']}.{kind}.json"
        if not ref.exists():
            return f"no-{kind}"
        r = json.loads(ref.read_text())
        if (r["samples"], r["total"]) != (j["samples"], j["total"]):
            return f"MISMATCH-{kind}"
    return "ok"


def series(run: Run, owner: str, counter: str = "cycles") -> list[float]:
    i = COUNTERS.index(counter)
    return [f[owner][i] for f in run.frames]


def steady(xs: list[float]) -> list[float]:
    return xs[WARMUP:] if len(xs) > WARMUP else xs


def fpu(base: Run, fl: Run | None, hw: dict[str, int]) -> list[float]:
    """Cart cycles per frame with an FPU: the soft-float cycles of the classes it
    implements are replaced by `hw` per call. Same frames, so frame f matches."""
    cart = series(base, "cart")
    if fl is None or len(fl.fclass) < len(cart):
        return []
    saved = [sum(cls[c][1] - cls[c][0] * hw[c] for c in hw) for cls in fl.fclass]
    return [c - s for c, s in zip(cart, saved, strict=False)]


def float_share(base: Run, fl: Run | None) -> float | None:
    if fl is None or not fl.fclass:
        return None
    soft = sum(sum(cls[c][1] for c in CLASSES_L) for cls in steady(fl.fclass))
    return soft / max(1.0, sum(steady(series(base, "cart"))))


def ddr(run: Run) -> list[float]:
    """Cart cycles per frame with the assumed DDR penalties added."""
    lines = [(f["cart"][1] + f["cart"][3]) / 8 for f in run.frames]  # ibus_ack + dbus_rd words / 8
    return [c + n * DDR_LINE + f["cart"][4] * DDR_STORE for c, n, f in zip(series(run, "cart"), lines, run.frames)]


def mc(x: float | None) -> str:
    return "-" if x is None else f"{x / 1e6:.2f}"


def mhz(x: float | None) -> str:
    return "-" if x is None else f"{x * 60 / 1e6:.0f}"


def p95(xs: list[float]) -> float | None:
    """The sustained load: a frame worse than this happens under 1 time in 20."""
    return sorted(xs)[int(0.95 * (len(xs) - 1))] if xs else None


def row(tag: str, runs: dict[str, Run]) -> list[str]:
    base, fl = runs.get("nobounds"), runs.get("float")
    if base is None:
        return []
    cart = steady(series(base, "cart"))
    al, st = runs.get("aligned"), runs.get("stock")
    share = float_share(base, fl)
    return [
        tag, ",".join(sorted({verify(tag, r) for r in runs.values()})), str(len(base.frames)),
        mc(mean(cart)), mc(p95(cart)), mc(max(cart)), mc(max(series(base, "cart")[:WARMUP] or [0])),
        mc(p95(steady(series(st, "cart"))) if st else None),
        mc(p95(steady(series(al, "cart"))) if al else None),
        mc(mean(steady(series(base, "mach")))), mc(mean(steady(series(base, "blit")))),
        "-" if share is None else f"{100 * share:.0f}%",
        mhz(p95(cart)), mhz(max(cart)), mhz(p95(steady(fpu(base, fl, HW_F)))),
        mhz(p95(steady(fpu(base, fl, HW_FD)))), mhz(p95(steady(fpu(al, fl, HW_F))) if al else None),
        mhz(p95(steady(ddr(base)))),
    ]  # fmt: skip


HEAD = [
    "cart", "hashes", "frames", "cart avg Mc", "cart p95 Mc", "cart max Mc", "first max Mc", "stock p95 Mc",
    "aligned p95 Mc", "machine render avg Mc", "blitter avg Mc", "float share", "MHz soft p95", "MHz soft max",
    "MHz FPU p95", "MHz FPU F+D p95", "MHz FPU+aligned p95", "MHz soft+DDR p95",
]  # fmt: skip


def load() -> dict[str, dict[str, Run]]:
    out: dict[str, dict[str, Run]] = {}
    for log in sorted((CYC / "uart").glob("*/*.txt")):
        run = parse(log)
        if run.frames:
            out.setdefault(log.stem, {})[log.parent.name] = run
    return out


def details(tag: str, runs: dict[str, Run]) -> list[str]:
    out = []
    for v, r in sorted(runs.items()):
        bus = [mean(steady(series(r, "cart", c))) / 1e3 for c in COUNTERS[1:]]
        out.append(
            f"  {v:9} {verify(tag, r):14} end={r.end} boot={mc(r.boot)}Mc mis={r.misaligned} "
            f"cart bus/frame (k): " + " ".join(f"{c}={b:.0f}" for c, b in zip(COUNTERS[1:], bus))
        )
    fl = runs.get("float")
    if fl:
        top = sorted(((v[1], op, v[0]) for (op, o), v in fl.fops.items() if o == "cart"), reverse=True)[:8]
        out.append("  float ops (cart, whole run): " + ", ".join(f"{op} {n}x {c / 1e6:.1f}Mc" for c, op, n in top))
    return out


def main(argv: list[str]) -> None:
    del argv
    data = load()
    rows = [r for tag in sorted(data) if (r := row(tag, data[tag]))]
    widths = [max(len(x) for x in col) for col in zip(HEAD, *rows, strict=False)]
    lines = ["  ".join(x.ljust(w) for x, w in zip(r, widths, strict=False)) for r in [HEAD, *rows]]
    for tag in sorted(data):
        lines += ["", tag, *details(tag, data[tag])]
    (CYC / "report.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines[: len(rows) + 1]))
    md = FPGA / "CYCLES.md"
    if md.exists() and MARK_BEGIN in (text := md.read_text()):
        table = ["| " + " | ".join(HEAD) + " |", "|" + "---|" * len(HEAD)]
        table += ["| " + " | ".join(r) + " |" for r in rows]
        head, rest = text.split(MARK_BEGIN, 1)
        md.write_text(head + MARK_BEGIN + "\n" + "\n".join(table) + "\n" + MARK_END + rest.split(MARK_END, 1)[1])


if __name__ == "__main__":
    main([])
