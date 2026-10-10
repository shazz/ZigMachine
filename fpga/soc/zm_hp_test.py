"""hp-test: a bitstream with only the PS7's HP0 / HP1, the AXI masters that drive them,
and registers on GP0, so DDR / AFI behaviour is probed from U-Boot with `mw` / `md` in
seconds, without the cart CPU or the compositor (fpga/boards/microphase_z7_7010/README.md
"hp-test").

    make -C fpga hp-test     # -> fpga/build/hp_test/gateware/zm_hp_test.bit (~1 min)

Per port, two engines share one register bank and the port (CTRL.BRIDGE picks; change it
only while idle): the raw engine (soc/zm_hp_test_axi.py, every AXI field a register) and
the board SoC's own bridge (soc/zm_hp_test_bridge.py: WishboneHP on HP0, ZMVideoAXI on HP1..HP3).
`--ports 4` adds HP2 (the blitter's) and HP3 (the audio core's), banks 2 and 3; `--toolchain vivado`
builds it in ~3 min with sound primitives (openXC7 ones are suspect on silicon).
Register map, by byte offset from the GP0 base (0x43c0_0000): see BANK / GLOBAL below.
"""

from __future__ import annotations

import argparse
import dataclasses
import time
from pathlib import Path

from litex.gen import LiteXModule
from litex.soc.cores.clock import S7PLL
from litex.soc.interconnect import axi
from migen import Cat, ClockDomain, Constant, If, Mux, Signal

from soc import openxc7
from soc.zm_board_mem import ps7_instance
from soc.zm_hp import hp_interface
from soc.zm_hp_test_axi import AXIProbe, RunCfg
from soc.zm_hp_test_bridge import VideoRun, WishboneRun
from soc.zm_hp_test_regs import GP0Regs, gp0_interface

FPGA = Path(__file__).resolve().parent.parent
ID = 0x48505431  # "HPT1"
GLOBAL = {"ID": 0, "SCRATCH": 1, "MHZ": 2, "FREE": 3}  # word index; bank of port p at word 0x40 * (p + 1)
BANK = {"CTRL": 0, "ADDR": 1, "LEN": 2, "SIZE": 3, "CACHE": 4, "COUNT": 5, "STRB": 6, "SEED": 7,
        "STATUS": 8, "BEATS": 9, "ERRS": 10, "CYCLES": 11, "FIRST": 12, "D0LO": 13, "D0HI": 14, "BADIDX": 15}  # fmt: skip
CTRL_GO, CTRL_WRITE, CTRL_CHECK, CTRL_BRIDGE, CTRL_LINE, CTRL_LANE = 0, 1, 2, 3, 4, 5
DEFAULTS = {"ADDR": 0x0500_0000, "LEN": 15, "SIZE": 3, "CACHE": 0b0011, "COUNT": 1, "STRB": 0xFF, "SEED": 0x1000_0000}


def bank_base(port: int) -> int:
    return 0x40 * (port + 1)


class HPPort(LiteXModule):
    """One HP port: its register bank, the raw engine and the bridge, muxed onto `hp`."""

    def __init__(self, regs: GP0Regs, port: int, hp: axi.AXIInterface) -> None:
        base = bank_base(port)
        reg = {n: regs.storage(base + BANK[n], w, DEFAULTS[n]) for n, w in
               (("ADDR", 32), ("LEN", 4), ("SIZE", 3), ("CACHE", 4), ("COUNT", 16), ("STRB", 8), ("SEED", 32))}  # fmt: skip
        ctrl = regs.storage(base + BANK["CTRL"], 6)
        go = Signal()  # a cycle after the CTRL write, so the engines latch its new mode bits
        self.sync += go.eq(regs.strobe(base + BANK["CTRL"]) & regs.dat_w[CTRL_GO])
        self.bridge_sel = sel = ctrl[CTRL_BRIDGE]
        cfg = RunCfg(write=ctrl[CTRL_WRITE], check=ctrl[CTRL_CHECK], lane=ctrl[CTRL_LANE], addr=reg["ADDR"],
                     len=reg["LEN"], size=reg["SIZE"], cache=reg["CACHE"], count=reg["COUNT"], strb=reg["STRB"],
                     seed=reg["SEED"])  # fmt: skip
        raw_cfg, br_cfg = dataclasses.replace(cfg, go=Signal()), dataclasses.replace(cfg, go=Signal())
        self.comb += [raw_cfg.go.eq(go & ~sel), br_cfg.go.eq(go & sel)]
        raw_hp, br_hp = hp_interface(), hp_interface()
        self.raw = AXIProbe(raw_hp, raw_cfg)
        self.bridge = WishboneRun(br_hp, br_cfg, ctrl[CTRL_LINE]) if port == 0 else VideoRun(br_hp, br_cfg)
        self._mux(sel, raw_hp, br_hp, hp)
        self._status(regs, base)

    def _mux(self, sel: Signal, raw: axi.AXIInterface, br: axi.AXIInterface, hp: axi.AXIInterface) -> None:
        self.comb += If(sel, *br.connect(hp)).Else(*raw.connect(hp))

    def _status(self, regs: GP0Regs, base: int) -> None:
        r, b, sel = self.raw.stats, self.bridge.stats, self.bridge_sel
        fields = {"STATUS": (r.status_word(), b.status_word()), "BEATS": (r.beats, b.beats), "ERRS": (r.errs, b.errs),
                  "CYCLES": (r.cycles, b.cycles), "FIRST": (r.first, b.first), "D0LO": (r.d0[:32], b.d0[:32]),
                  "D0HI": (r.d0[32:], b.d0[32:]), "BADIDX": (r.badidx, b.badidx)}  # fmt: skip
        for name, (raw_v, br_v) in fields.items():
            sig = Signal(32, name=f"hpt_{name.lower()}_{base:x}")
            self.comb += sig.eq(Mux(sel, br_v, raw_v))
            regs.status(base + BANK[name], sig)


class HPTest(LiteXModule):
    """The whole bitstream's logic: the PS7, the registers, both ports, two LEDs."""

    def __init__(self, platform: object, sys_hz: int, ports: int = 2) -> None:
        self.crg = _CRG(platform, sys_hz)
        gp0, self.hp = gp0_interface(), [hp_interface() for _ in range(ports)]
        self.specials += ps7_instance(gp0, *self.hp)
        self.regs = regs = GP0Regs(gp0)
        regs.status(GLOBAL["ID"], Constant(ID, 32))  # a constant, not an undriven reg Yosys may drop
        regs.storage(GLOBAL["SCRATCH"])
        regs.status(GLOBAL["MHZ"], Constant(sys_hz // 1_000_000, 32))
        free = Signal(32)
        self.sync += free.eq(free + 1)
        regs.status(GLOBAL["FREE"], free)
        hp_ports = [HPPort(regs, i, hp) for i, hp in enumerate(self.hp)]
        for i, port in enumerate(hp_ports):
            setattr(self, f"port{i}", port)
        req = platform.request  # type: ignore[attr-defined]  # untyped LiteX platform
        busy = Signal()
        self.comb += busy.eq(Cat(*[p.raw.stats.busy | p.bridge.stats.busy for p in hp_ports]) != 0)
        self.comb += [req("PL_LED1").eq(free[26]), req("PL_LED2").eq(busy)]  # alive at ~0.7 Hz; a run in flight


class _CRG(LiteXModule):
    def __init__(self, platform: object, sys_hz: int) -> None:
        self.cd_sys = ClockDomain()
        self.pll = pll = S7PLL(speedgrade=-1)
        clkin = platform.request("PL_CLK_50M")  # type: ignore[attr-defined]  # untyped LiteX platform
        platform.add_period_constraint(clkin, 20.0)  # type: ignore[attr-defined]  # untyped LiteX platform
        pll.register_clkin(clkin, 50e6)
        pll.create_clkout(self.cd_sys, sys_hz)


def main() -> None:
    from soc import litex_compat
    from soc.platform_z7 import Platform

    p = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    p.add_argument("--sys-mhz", type=float, default=100.0, help="the HP ports' clock (the board SoC's sys)")
    p.add_argument("--out", default=str(FPGA / "build/hp_test"), help="the build directory")
    p.add_argument("--build", action="store_true", help="run the toolchain (else: Verilog + scripts only)")
    p.add_argument("--toolchain", choices=["openxc7", "vivado"], default="openxc7")
    p.add_argument("--ports", type=int, choices=[2, 4], default=2, help="4: also HP2 and HP3")
    a = p.parse_args()
    start = time.monotonic()
    litex_compat.install()
    platform = Platform(toolchain=a.toolchain)
    top = HPTest(platform, int(a.sys_mhz * 1e6), a.ports)
    gateware = Path(a.out) / "gateware"
    vivado = a.toolchain == "vivado"
    if a.build and not vivado:
        openxc7.prepare_env()
    platform.build(top, build_dir=str(gateware), build_name="zm_hp_test", run=a.build and vivado)
    if a.build and not vivado:
        openxc7.run_build(str(gateware), "zm_hp_test", time.monotonic() - start)


if __name__ == "__main__":
    main()
