"""LUTs and FFs of the blitter's HP2 bridge (soc/zm_blit_hp.py) per `burst`, from a Yosys
synth_xilinx of the bridge alone (yowasp, no Vivado): what soc/zm_blit_wburst.py adds.

    uv run python tools/blit_hp_synth.py [burst ...]      default: 0 4 8

An estimate for the 7-series LUT budget, not Vivado's number: Yosys maps LUTRAM and carry
chains a little differently, so compare the rows against each other."""

from __future__ import annotations

import re
import sys
from pathlib import Path

import yowasp_yosys
from migen import Module, Signal
from migen.fhdl import verilog

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA))
from soc.zm_blit_hp import BlitHP  # noqa: E402 -- after the path insert
from soc.zm_hp import hp_interface  # noqa: E402

OUT = FPGA / "build" / "blit_hp_synth"


class Top(Module):
    """The bridge with every port a named top-level signal (Migen names ios by their own names)."""

    def __init__(self, burst: int) -> None:
        hp = hp_interface()
        self.base, self.enable = Signal(32, name="base"), Signal(name="enable")
        self.submodules.mem = m = BlitHP(hp, self.base, self.enable, burst=burst)
        self.ios = {self.base, self.enable}
        outs = ("rd_req_ready", "rd_rsp_valid", "rd_rsp_data", "wr_req_ready", "wr_pending")
        ins = ("rd_req_valid", "rd_req_addr", "wr_req_valid", "wr_req_addr", "wr_req_data", "wr_req_strb")
        for n in outs + ins:
            self._port(n, getattr(m, n), n in outs)
        for ch in (hp.aw, hp.w, hp.b, hp.ar, hp.r):
            for sig, direction in ch.iter_flat():  # DIR_M_TO_S (2): the bridge drives it
                self._port(sig.backtrace[-1][0], sig, direction == 2)

    def _port(self, name: str, sig: Signal, out: bool) -> None:
        p = Signal(len(sig), name=name)
        self.ios.add(p)
        self.comb += p.eq(sig) if out else sig.eq(p)


def synth(burst: int) -> tuple[int, int, int]:
    OUT.mkdir(parents=True, exist_ok=True)
    top = Top(burst)
    src = OUT / f"blit_hp_{burst}.v"
    src.write_text(str(verilog.convert(top, ios=top.ios, name="blit_hp")))
    log = OUT / f"blit_hp_{burst}.log"
    script = f"read_verilog {src}; synth_xilinx -top blit_hp -family xc7 -flatten; tee -o {log} stat"
    assert yowasp_yosys.run_yosys(["-q", "-p", script]) == 0, "yosys failed"
    text = log.read_text()
    luts = sum(int(n) for n in re.findall(r"^\s+(\d+)\s+LUT\d", text, re.MULTILINE))
    luts += 4 * sum(int(n) for n in re.findall(r"^\s+(\d+)\s+RAM32M", text, re.MULTILINE))
    luts += sum(int(n) for n in re.findall(r"^\s+(\d+)\s+RAM(?:32X1D|64X1D|32X1S|64X1S)", text, re.MULTILINE))
    carry = sum(int(n) for n in re.findall(r"^\s+(\d+)\s+CARRY4", text, re.MULTILINE))
    ffs = sum(int(n) for n in re.findall(r"^\s+(\d+)\s+FD[RSCPE]+", text, re.MULTILINE))
    return luts, ffs, carry


def main() -> None:
    bursts = [int(a) for a in sys.argv[1:]] or [0, 4, 8]
    for b in bursts:
        luts, ffs, carry = synth(b)
        print(f"burst {b}: ~{luts} LUT (a RAM32M as 4), {ffs} FF, {carry} CARRY4")


if __name__ == "__main__":
    main()
