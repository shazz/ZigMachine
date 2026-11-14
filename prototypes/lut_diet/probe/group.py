"""Bill the leaf cells of dump_cells.tcl by hierarchy, type and name prefix.

usage: group.py cells.txt [hier-prefix]  (the prefix narrows the name-prefix table to one block)
"""
from __future__ import annotations

import re
import sys
from collections import Counter, defaultdict

MODULES = ("VexRiscv", "ZmSnd_VexRiscv", "zm_audio_soc", "zm_blit", "zm_glass_osd", "zm_glass_regs",
           "zm_hdmi_out", "zm_video_out", "zm_seal")


def kind(ref: str) -> str:
    if ref.startswith("LUT"):
        return "LUT"
    if ref.startswith("FD"):
        return "FF"
    if ref.startswith("RAMB"):
        return ref
    if ref.startswith(("RAMD", "RAMS")):
        return "LUTRAM"
    if ref.startswith("SRL"):
        return "SRL"
    return ref


def top_block(name: str) -> str:
    head = name.split("/")[0]
    return head if head in MODULES else "(top)"


def prefix(name: str, depth: int) -> str:
    """A name's first `depth` underscore tokens after the LiteX make_z7_ / zigmachinesoc_ wrappers."""
    n = name.split("/")[-1]
    n = re.sub(r"^(make_z7_|builder_)", "", n)
    n = re.sub(r"^(zigmachinesoc_)+", "", n)
    n = re.sub(r"(_reg)?(\[\d+\])?(_i_\d+|_n_\d+)*(_rep(N)?\d*)?(__\d+)?$", "", n)
    return "_".join(n.split("_")[:depth])


def main() -> None:
    rows = [line.split() for line in open(sys.argv[1]) if line.strip()]
    narrow = sys.argv[2] if len(sys.argv) > 2 else None
    by_block: dict[str, Counter] = defaultdict(Counter)
    for name, ref in rows:
        by_block[top_block(name)][kind(ref)] += 1
    print("== by top-level block")
    for b, c in sorted(by_block.items(), key=lambda kv: -kv[1]["LUT"]):
        print(f"{b:18s}", " ".join(f"{k}={v}" for k, v in sorted(c.items(), key=lambda kv: -kv[1])))
    print("\n== DSP48E1 cells")
    for name, ref in rows:
        if ref == "DSP48E1":
            print("  ", name)
    print("\n== CARRY4 by block / prefix")
    cc: Counter = Counter()
    for name, ref in rows:
        if ref == "CARRY4":
            cc[(top_block(name), prefix(name, 3))] += 1
    for (b, p), v in cc.most_common(40):
        print(f"  {v:4d} {b} {p}")
    scope = narrow or "(top)"
    print(f"\n== {scope}: LUT and FF by name prefix (depth 3)")
    pc: dict[str, Counter] = defaultdict(Counter)
    for name, ref in rows:
        blk = top_block(name)
        if narrow is None and blk != "(top)":
            continue
        if narrow is not None and not name.startswith(narrow):
            continue
        pc[prefix(name, 3)][kind(ref)] += 1
    for p, c in sorted(pc.items(), key=lambda kv: -(kv[1]["LUT"] + kv[1]["FF"] * 0.25))[:60]:
        print(f"  {p:48s}", " ".join(f"{k}={v}" for k, v in sorted(c.items(), key=lambda kv: -kv[1])))


main()
