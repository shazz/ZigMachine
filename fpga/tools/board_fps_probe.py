"""The video probe's fields of the ZMSTAT line (fpga/glass/src/vstat.zig, cycles/vstat.h), for
tools/board_fps.py: the CSV keeps them raw, the .md gets a per-pass table.

Every figure is a per-frame mean over the firmware's last window (vs_n frames), in sys cycles
(100 MHz) but comp_busy, in compositor clocks (125 MHz). A firmware without the probe says `-`.
"""

from __future__ import annotations

FIELDS = (
    "vs_n", "frame_c", "cart_c", "seq_c", "wait_ready", "drain", "painted", "hbl", "plan", "passes",
    "comp_busy", "dma_busy", "swap", "underrun", "overflow", "probe_c",
    "cal_mix1", "cal_mix2", "cal_fill1", "cal_fill2",
)  # fmt: skip
SYS_PER_COMP = 100 / 125  # sys cycles per compositor clock on the board (soc/zm_z7.py)
COLS = ("cart", "fps", "frame_c", "cart_c", "seq_c", "passes", "seq/pass", "painted/pass", "ready/pass",
        "comp/pass", "hbl", "plan", "swap", "underrun")  # fmt: skip
PER_PASS = (("seq/pass", "seq_c", 1.0), ("painted/pass", "painted", 1.0), ("ready/pass", "wait_ready", 1.0),
            ("comp/pass", "comp_busy", SYS_PER_COMP))  # fmt: skip


def _num(row: dict[str, str], key: str) -> float | None:
    try:
        return float(row.get(key, "-"))
    except ValueError:
        return None


def per_pass(row: dict[str, str]) -> dict[str, str]:
    """One .md row: the means, and the sequencer's figures divided by the passes issued."""
    out = {k: row.get(k, "-") for k in COLS}
    passes = _num(row, "passes")
    for col, key, scale in PER_PASS:
        v = _num(row, key)
        out[col] = f"{v * scale / passes:.0f}" if v is not None and passes else "-"
    return out


def md_table(rows: list[dict[str, str]]) -> list[str]:
    """The probe's table, or nothing when no row has the probe."""
    probed = [r for r in rows if r.get("vs_n", "-") != "-"]
    if not probed:
        return []
    lines = ["", "FRESCO probe (sys cycles per frame; /pass: per BG/PLANE/MIX pass; comp/pass in sys cycles):", ""]
    lines += ["| " + " | ".join(COLS) + " |", "|" + "---|" * len(COLS)]
    lines += ["| " + " | ".join(per_pass(r)[c] for c in COLS) + " |" for r in probed]
    cal = next((r for r in probed if r.get("cal_mix1", "-") != "-"), None)
    if cal:
        cals = ", ".join(f"{k}={cal[k]}" for k in FIELDS[-4:])
        lines += ["", f"Row costs at boot ({cal['cart']}; span sys / comp clocks): {cals}"]
    return lines
