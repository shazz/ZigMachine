"""The board's read path around the real cart core, for tests/test_ziggy_reads.py
(review/ZIGGY_BIG_READS_STUDY.md): VexRiscv (the board netlist) -> LiteX's shared Wishbone
(Arbiter + Decoder, as the SoC builds it) -> WishboneHP (posted=8, as the board) -> the HP
register slices (zm_board_mem.hp_slice's shape) -> ZMSimAXIRAM with an AR-to-first-beat
latency. Only the cart window is DDR; byte address bit 31 is a device the C++ harness
answers (tests/tb/zigread_tb.cpp: exit, cycle counter, REPORT lines), the uncached IO space.

    uv run python tests/zigread_top.py OUT.v [--latency 20] [--fast-burst] [--prefetch]
"""

from __future__ import annotations

import argparse
from typing import Any

from litex.gen import LiteXModule
from litex.soc.interconnect import stream, wishbone
from migen import ClockDomain, Instance, Signal
from migen.fhdl import verilog

from soc.zm_hp import DDR_BASE, WishboneHP, hp_interface
from soc.zm_simaxi import ZMSimAXIRAM

RAM = 4 << 20  # the sim's DDR: the test's code, stack and buffers (tests/dcache/link.ld)
BUS = ("cyc", "stb", "ack", "we", "adr", "dat_r", "dat_w", "sel", "err", "cti", "bte")


def _slices(m: LiteXModule, master: Any) -> Any:  # Any: LiteX AXI interfaces are untyped
    """zm_board_mem.hp_slice without the glass: a pipe_valid register on every channel."""
    ps = hp_interface()
    for ch, out in (("aw", True), ("w", True), ("ar", True), ("b", False), ("r", False)):
        src, dst = (getattr(master, ch), getattr(ps, ch)) if out else (getattr(ps, ch), getattr(master, ch))
        buf = stream.Buffer(src.description, pipe_valid=True, pipe_ready=False)
        setattr(m, f"slice_{ch}", buf)
        m.comb += [src.connect(buf.sink), buf.source.connect(dst)]
    return ps


class ReadTop(LiteXModule):
    def __init__(self, netlist_top: str, latency: int, **hp_kw: Any) -> None:
        self.clock_domains.cd_sys = ClockDomain()
        self.dev = wishbone.Interface(data_width=32, address_width=32, addressing="word")
        ibus, dbus, shared, ram = (
            wishbone.Interface(data_width=32, address_width=32, addressing="word") for _ in range(4)
        )
        self.cpu_irq = Signal(32)
        self.specials += Instance(
            netlist_top, i_clk=self.cd_sys.clk, i_reset=self.cd_sys.rst, i_externalResetVector=0x40000000,
            i_timerInterrupt=0, i_softwareInterrupt=0, i_externalInterruptArray=self.cpu_irq,
            **{f"{d}_iBusWishbone_{n}": getattr(ibus, s) for d, n, s in _dirs()},
            **{f"{d}_dBusWishbone_{n}": getattr(dbus, s) for d, n, s in _dirs()},
        )  # fmt: skip
        self.arbiter = wishbone.Arbiter([ibus, dbus], shared)
        self.decoder = wishbone.Decoder(shared, [(lambda a: ~a[29], ram), (lambda a: a[29], self.dev)])
        self.hp = hp_interface()
        self.bridge = WishboneHP(ram, self.hp, 8, **hp_kw)
        if hasattr(self.bridge, "io_kill"):  # the prefetch's IO rule: the CPU's D-bus in the IO space
            self.comb += self.bridge.io_kill.eq(dbus.cyc & dbus.stb & dbus.adr[29])
        ps = _slices(self, self.hp)
        self.ddr = ZMSimAXIRAM(RAM, [ps], latency=latency, wr32=True, reads=8, base=DDR_BASE)
        self.ios = {self.cd_sys.clk, self.cd_sys.rst, *(getattr(self.dev, s) for s in BUS)}


def _dirs() -> list[tuple[str, str, str]]:
    """(Instance direction, VexRiscv port suffix, Wishbone signal) for a VexRiscv master port."""
    outs = ("cyc", "stb", "we", "adr", "dat_w", "sel", "cti", "bte")
    names = {"dat_r": "DAT_MISO", "dat_w": "DAT_MOSI"}
    return [("o" if s in outs else "i", names.get(s, s.upper()), s) for s in BUS]


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("out")
    p.add_argument("--latency", type=int, default=20)
    p.add_argument("--opt", action="append", default=[], help="a WishboneHP keyword set True, e.g. fast_burst")
    p.add_argument("--break", dest="break_", default="", help="the prefetch's mutant (soc/zm_hp_prefetch.py BREAKS)")
    a = p.parse_args()
    kw: dict[str, Any] = {k: True for k in a.opt} | ({"read_break": a.break_} if a.break_ else {})
    top = ReadTop("VexRiscv", a.latency, **kw)
    verilog.convert(top, ios=top.ios, name="zigread").write(a.out)  # + its zm_ddr.init (zeros), in the cwd


if __name__ == "__main__":
    main()
