"""Yosys synth_xilinx (in-process yowasp, no Vivado) of WishboneHP posted=8, read bypass off vs on:
a LUT/FF estimate of the bypass alone. Run from fpga/:
    uv run python ../prototypes/read_bypass_re/lut_estimate.py [tag bits]"""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yowasp_yosys
from litex.soc.interconnect import wishbone
from migen.fhdl.verilog import convert

sys.path.insert(0, ".")
from soc import zm_hp_bypass
from soc.zm_hp import WishboneHP, hp_interface

OUT = Path(__file__).parent / "build"
CELL = re.compile(r"^\s+(\d+)\s+(LUT[1-6]|FDRE|FDSE|RAM32M|CARRY4|MUXF[78])\s*$", re.MULTILINE)


def cells(bypass: bool) -> dict[str, int]:
    bus = wishbone.Interface(data_width=32, address_width=32, addressing="word")
    hp = hp_interface()
    ios = set(bus.flatten())
    for ch in ("aw", "w", "b", "ar", "r"):
        ios |= set(getattr(hp, ch).flatten())
    OUT.mkdir(exist_ok=True)
    v, st = OUT / f"hp_{int(bypass)}.v", OUT / f"hp_{int(bypass)}.stat"
    convert(WishboneHP(bus, hp, 8, bypass), ios=ios, name="hp").write(str(v))
    rc = yowasp_yosys.run_yosys(["-q", "-p", f"read_verilog {v}; synth_xilinx -top hp -flatten; tee -o {st} stat"])
    assert rc == 0
    return {k: int(n) for n, k in CELL.findall(st.read_text())}


if __name__ == "__main__":
    if len(sys.argv) > 1:  # a narrower tag: `lut_estimate.py 12` (a hashed compare's cost, more false clashes)
        zm_hp_bypass.LINE_TAG = int(sys.argv[1])
    off, on = cells(False), cells(True)
    for k in sorted(set(off) | set(on)):
        print(f"{k:7} off {off.get(k, 0):5}  on {on.get(k, 0):5}  +{on.get(k, 0) - off.get(k, 0)}")
    luts = [sum(v for k, v in d.items() if k.startswith("LUT")) for d in (off, on)]
    print(f"LUT total off {luts[0]}  on {luts[1]}  +{luts[1] - luts[0]}")
