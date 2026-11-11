"""LUTs and FFs of ZIGGY's HP0 bridge (soc/zm_hp.py WishboneHP, posted=8, no read bypass: the
board's combo16 build) per read mode (soc/zm_board_mem.py READ_MODES), from a Yosys
synth_xilinx of the bridge alone (yowasp, no Vivado): review/ZIGGY_BIG_READS_STUDY.md.

    uv run python tools/hp_read_synth.py [mode ...]      default: base fast prefetch

An estimate for comparing the rows, not Vivado's number (tools/blit_hp_synth.py's caveat)."""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yowasp_yosys
from litex.soc.interconnect import wishbone
from migen import Module, Signal
from migen.fhdl import verilog

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA))
from soc.zm_board_mem import READ_MODES
from soc.zm_hp import WishboneHP, hp_interface

OUT = FPGA / "build" / "hp_read_synth"


class Top(Module):
    """The bridge with every port a named top-level signal."""

    def __init__(self, mode: str) -> None:
        bus, hp = wishbone.Interface(data_width=32, address_width=32, addressing="word"), hp_interface()
        self.submodules.hp = m = WishboneHP(bus, hp, 8, **READ_MODES[mode])
        self.ios: set[Signal] = set()
        outs = {"ack", "dat_r", "err"}
        for name in ("cyc", "stb", "we", "adr", "dat_w", "sel", "cti", "ack", "dat_r"):
            self._port(f"wb_{name}", getattr(bus, name), name in outs)
        if hasattr(m, "io_kill"):
            self._port("io_kill", m.io_kill, False)
        self._port("idle", m.idle, True)
        for ch in (hp.aw, hp.w, hp.b, hp.ar, hp.r):
            inbound = ch is hp.b or ch is hp.r  # the PS drives these streams: the bridge is their sink
            for sig, direction in ch.iter_flat():  # DIR_M_TO_S (2): the stream's source drives it
                self._port(sig.backtrace[-1][0], sig, (direction == 2) != inbound)

    def _port(self, name: str, sig: Signal, out: bool) -> None:
        p = Signal(len(sig), name=name)
        self.ios.add(p)
        self.comb += p.eq(sig) if out else sig.eq(p)


def synth(mode: str) -> tuple[int, int]:
    OUT.mkdir(parents=True, exist_ok=True)
    top = Top(mode)
    src = OUT / f"hp_{mode}.v"
    src.write_text(str(verilog.convert(top, ios=top.ios, name="hp_read")))
    log = OUT / f"hp_{mode}.log"
    script = f"read_verilog {src}; synth_xilinx -top hp_read -family xc7 -flatten; tee -o {log} stat"
    assert yowasp_yosys.run_yosys(["-q", "-p", script]) == 0, "yosys failed"
    text = log.read_text()
    luts = sum(int(n) for n in re.findall(r"^\s+(\d+)\s+LUT\d", text, re.MULTILINE))
    luts += 4 * sum(int(n) for n in re.findall(r"^\s+(\d+)\s+RAM32M", text, re.MULTILINE))
    luts += sum(int(n) for n in re.findall(r"^\s+(\d+)\s+RAM(?:32X1D|64X1D|32X1S|64X1S)", text, re.MULTILINE))
    ffs = sum(int(n) for n in re.findall(r"^\s+(\d+)\s+FD[RSCPE]+", text, re.MULTILINE))
    return luts, ffs


def main() -> None:
    for mode in sys.argv[1:] or list(READ_MODES):
        luts, ffs = synth(mode)
        print(f"{mode:9}: ~{luts} LUT (a RAM32M as 4), {ffs} FF")


if __name__ == "__main__":
    main()
