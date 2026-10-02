"""The glass (rtl/glass/) as LiteX blocks, for the board (docs/FPGA_GLASS.md).

- `ZMGlass`: the register block. Its AXI3 slave hangs off the PS's M_AXI_GP0
  (`ps7_gp0` wires a PS7 instance to it, clocked from sys so the whole block
  lives in one domain). Its cart side becomes CSRs the cart CPU's firmware
  reads: the key FIFO, the joypad, and the state and heartbeat it reports.
  `cpu_run` holds the cart CPU in reset until the ARM has placed a cart.
- `overlay`: the OSD, as the hook soc/zm_video_pipe.py calls between the
  scanout and the DVI encoder (pixel clock).
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from litex.gen import LiteXModule
from litex.soc.interconnect import axi
from litex.soc.interconnect.csr import CSRStatus, CSRStorage
from migen import ClockSignal, Instance, ResetSignal, Signal

FPGA = Path(__file__).resolve().parent.parent
SOURCES = [FPGA / "rtl/glass/zm_glass_regs.v", FPGA / "rtl/glass/zm_glass_osd.v"]

# LiteX platforms are untyped Python classes with no common base worth naming.
Platform = Any
Picture = dict[str, Signal]


class ZMGlass(LiteXModule):
    def __init__(self, platform: Platform) -> None:
        self.axi = axi.AXIInterface(data_width=32, address_width=32, id_width=12, version="axi3")
        self.cpu_run = Signal()
        self.osd = {"en": Signal(), "fg": Signal(24), "bg": Signal(24)}
        self.osd_write = {"we": Signal(), "waddr": Signal(9), "wdata": Signal(9)}
        self.key_data = CSRStatus(32, description="The oldest key event (fpga/glass/src/map.zig, KEY_*).")
        self.key_valid = CSRStatus(1, description="key_data holds an event.")
        self.key_pop = CSRStorage(1, description="Write anything: drop key_data, show the next event.")
        self.joy = CSRStatus(8, description="Joypad bits held now (JOY_*).")
        self.cart_state = CSRStorage(32, description="The firmware's state for the ARM (CART_*).")
        self.cart_beat = CSRStorage(32, description="Frames the firmware has finished: the ARM's watchdog.")
        self.specials += Instance("zm_glass_regs", **self._ports())
        for src in SOURCES:
            platform.add_source(str(src))
        platform.add_verilog_include_path(str(FPGA / "gen"))

    def _ports(self) -> dict[str, object]:
        a = self.axi
        return {
            "i_clk": ClockSignal("sys"), "i_rst": ResetSignal("sys"),
            "i_s_awvalid": a.aw.valid, "o_s_awready": a.aw.ready, "i_s_awaddr": a.aw.addr[:16], "i_s_awid": a.aw.id,
            "i_s_wvalid": a.w.valid, "o_s_wready": a.w.ready, "i_s_wdata": a.w.data, "i_s_wstrb": a.w.strb,
            "o_s_bvalid": a.b.valid, "i_s_bready": a.b.ready, "o_s_bid": a.b.id, "o_s_bresp": a.b.resp,
            "i_s_arvalid": a.ar.valid, "o_s_arready": a.ar.ready, "i_s_araddr": a.ar.addr[:16], "i_s_arid": a.ar.id,
            "o_s_rvalid": a.r.valid, "i_s_rready": a.r.ready, "o_s_rdata": a.r.data, "o_s_rid": a.r.id,
            "o_s_rresp": a.r.resp, "o_s_rlast": a.r.last,
            "o_cpu_run": self.cpu_run, "o_osd_en": self.osd["en"], "o_osd_fg": self.osd["fg"],
            "o_osd_bg": self.osd["bg"], "o_load_base": Signal(32), "o_load_size": Signal(32),
            "o_joy": self.joy.status, "o_osd_we": self.osd_write["we"], "o_osd_waddr": self.osd_write["waddr"],
            "o_osd_wdata": self.osd_write["wdata"], "o_key_valid": self.key_valid.status,
            "o_key_data": self.key_data.status, "i_key_pop": self.key_pop.re,
            "i_cart_state_we": self.cart_state.re, "i_cart_state_in": self.cart_state.storage,
            "i_cart_beat_we": self.cart_beat.re, "i_cart_beat_in": self.cart_beat.storage,
        }  # fmt: skip

    def overlay(self, module: LiteXModule, pic: Picture, cd_pix: str = "pix") -> Picture:
        """Lay the OSD over `pic` (the scanout's r g b de hsync vsync); returns what DVI should send."""
        out = {k: Signal(len(v), name=f"osd_{k}") for k, v in pic.items()}
        module.specials += Instance(
            "zm_glass_osd",
            i_clk=ClockSignal(cd_pix), i_rst=ResetSignal(cd_pix), i_en=self.osd["en"],
            i_fg=self.osd["fg"], i_bg=self.osd["bg"], i_wclk=ClockSignal("sys"),
            i_we=self.osd_write["we"], i_waddr=self.osd_write["waddr"], i_wdata=self.osd_write["wdata"],
            i_r=pic["r"], i_g=pic["g"], i_b=pic["b"], i_de=pic["de"], i_hsync=pic["hsync"], i_vsync=pic["vsync"],
            o_r_o=out["r"], o_g_o=out["g"], o_b_o=out["b"], o_de_o=out["de"], o_hs_o=out["hsync"],
            o_vs_o=out["vsync"],
        )  # fmt: skip
        return out


def ps7_gp0(gp0: axi.AXIInterface) -> Instance:
    """The PS7 primitive with only M_AXI_GP0 in use (MAXIGP0*), clocked from sys.

    The PS itself is configured by the FSBL in BOOT.BIN (zeST's for now), not
    by this cell: the PL only needs it so the GP0 wires exist. Its DDR and MIO
    pins are the PS's own dedicated balls and stay unconnected here.
    """
    p = "MAXIGP0"
    ports: dict[str, object] = {f"i_{p}ACLK": ClockSignal("sys")}
    for ch in ("AW", "AR"):
        sub = getattr(gp0, ch.lower())
        for f in ("valid", "addr", "burst", "len", "id", "lock", "prot", "cache", "qos"):
            ports[f"o_{p}{ch}{f.upper()}"] = getattr(sub, f)
        ports[f"o_{p}{ch}SIZE"] = sub.size[:2]  # 2 bits on the primitive: GP0 beats are at most 4 bytes
        ports[f"i_{p}{ch}READY"] = sub.ready
    ports.update({
        f"o_{p}WVALID": gp0.w.valid, f"o_{p}WLAST": gp0.w.last, f"i_{p}WREADY": gp0.w.ready,
        f"o_{p}WID": gp0.w.id, f"o_{p}WDATA": gp0.w.data, f"o_{p}WSTRB": gp0.w.strb,
        f"i_{p}BVALID": gp0.b.valid, f"o_{p}BREADY": gp0.b.ready, f"i_{p}BID": gp0.b.id, f"i_{p}BRESP": gp0.b.resp,
        f"i_{p}RVALID": gp0.r.valid, f"o_{p}RREADY": gp0.r.ready, f"i_{p}RLAST": gp0.r.last,
        f"i_{p}RID": gp0.r.id, f"i_{p}RRESP": gp0.r.resp, f"i_{p}RDATA": gp0.r.data,
    })  # fmt: skip
    return Instance("PS7", **ports)
