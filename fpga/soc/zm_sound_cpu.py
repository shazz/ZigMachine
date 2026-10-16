"""The sound CPU (docs/FPGA_SOUND_CPU.md): a second VexRiscv that runs the machine's
players (the SNDH player = Musashi, via wasm2c) instead of the cart CPU.

- **The core**: vexgen's `SndNd` netlist (`vexgen/gen.sh SndNd:16384:2:4096:1:snd,nodiv`): RV32I + Zmmul
  (no divider, DIV/REM trap: the firmware divides in libgcc, cycles/sound.mk SND_ARCH), 16 KiB 2-way I$,
  4 KiB D$, every module prefixed ZmSnd_ so it sits next to the cart CPU's VexRiscv. Reset vector
  SOUND_BASE, in the cart window (cycles/sound.mk links there).
- **Its memory is the cart window in DDR, on HP3**, which it shares with the audio core's
  PCM reads: one Wishbone arbiter (I-bus, D-bus to DDR, the core's `PcmWB`) in front of
  one WishboneHP, with POSTED stores (soc/zm_hp_posted.py: the player's Musashi stores
  ~20 times per 68000 instruction). A PCM read waits for the posted stores like any read,
  so the core hears what the players wrote.
- **Its D-bus also reaches** AUDIO_WINDOW (the core's stamped write queue, moved here from
  the cart CPU's bus: only the players push writes) and its side of SOUND_WINDOW
  (soc/zm_sound_regs.py: the mailbox, CTRL.RUN, its counters, the sim console).
- **The cart CPU sees SOUND_WINDOW only**: it loads the sound image into DDR, sets RUN, and
  forwards the cart's song requests as mailbox commands (cycles/bsound.c).
- **Held in reset** while RUN is low or the glass holds the cart CPU (CTRL.RUN of the glass):
  no HP3 traffic across a PL reload, as for every HP master here.
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from litex.gen import LiteXModule
from litex.soc.integration.soc import SoCRegion
from litex.soc.interconnect import axi, wishbone
from migen import ClockSignal, Instance, ResetSignal, Signal

from soc.zm_audio_soc import AUDIO_WINDOW, AUDIO_WINDOW_BYTES, ZMAudio
from soc.zm_hp import CPU_BASE, WINDOW, WishboneHP
from soc.zm_sound_regs import SoundRegs

FPGA = Path(__file__).resolve().parent.parent
SOUND_CORE = FPGA / "build/vexgen/VexRiscv_SndNd.v"
SOUND_WINDOW = 0x93000000  # uncached (bit 31), outside the seal's windows, next to AUDIO_WINDOW
SOUND_WINDOW_BYTES = 0x1000
SOUND_BASE = CPU_BASE + 0x00E00000  # the sound image: 14 MiB into the cart window, above the pictures (cycles/sound.mk)
POSTED = 8

# LiteX platforms and SoCs: untyped, their submodules are attributes made at runtime.
Platform = Any
SoC = Any


def _wb() -> wishbone.Interface:
    return wishbone.Interface(data_width=32, address_width=32, addressing="word")


def _in(base: int, size: int) -> Any:  # Any: a Migen comparison, the decoder's slave test
    shift = (size // 4).bit_length() - 1  # word-address bits inside the region
    return lambda adr: adr[shift:30] == (base >> 2) >> shift


def _core_ports(prefix: str, bus: wishbone.Interface) -> dict[str, Any]:
    p = f"{prefix}Wishbone_"
    return {
        f"o_{p}CYC": bus.cyc, f"o_{p}STB": bus.stb, f"o_{p}WE": bus.we, f"o_{p}ADR": bus.adr[:30],
        f"o_{p}DAT_MOSI": bus.dat_w, f"o_{p}SEL": bus.sel, f"o_{p}CTI": bus.cti, f"o_{p}BTE": bus.bte,
        f"i_{p}ACK": bus.ack, f"i_{p}DAT_MISO": bus.dat_r, f"i_{p}ERR": 0,
    }  # fmt: skip


class SoundCPU(LiteXModule):
    """The core, its decoder and HP3 bridge; `cart` is SOUND_WINDOW's slave on the cart CPU's bus."""

    def __init__(self, platform: Platform, hp: axi.AXIInterface, audio: wishbone.Interface, pcm: wishbone.Interface,
                 enable: Signal | None = None, core: Path = SOUND_CORE) -> None:  # fmt: skip
        if not core.exists():
            raise FileNotFoundError(f"{core}: generate it with vexgen/gen.sh SndNd:16384:2:4096:1:snd,nodiv")
        self.cart = _wb()
        ibus, dbus, dmem, regs, mem = _wb(), _wb(), _wb(), _wb(), _wb()
        self.regs = SoundRegs(self.cart, regs, ibus, dbus)
        rst = ResetSignal("sys") | ~self.regs.run | (~enable if enable is not None else 0)
        self.specials += Instance(
            "ZmSnd_VexRiscv", i_clk=ClockSignal("sys"), i_reset=rst, i_externalResetVector=SOUND_BASE,
            i_timerInterrupt=0, i_softwareInterrupt=0, i_externalInterruptArray=0,
            **_core_ports("iBus", ibus), **_core_ports("dBus", dbus),
        )  # fmt: skip
        slaves = [
            (_in(CPU_BASE, WINDOW), dmem),
            (_in(AUDIO_WINDOW, AUDIO_WINDOW_BYTES), audio),
            (_in(SOUND_WINDOW, SOUND_WINDOW_BYTES), regs),
        ]
        self.decoder = wishbone.Decoder(dbus, slaves, register=True)
        self.arbiter = wishbone.Arbiter([ibus, dmem, pcm], mem)
        self.bridge = WishboneHP(mem, hp, POSTED)
        # PUTC: the sim's console, an empty module in synthesis.
        self.specials += Instance("zm_snd_putc", i_clk=ClockSignal("sys"), i_we=self.regs.putc, i_c=self.regs.char)
        platform.add_source(str(core))
        platform.add_source(str(FPGA / "rtl/sim/zm_snd_putc.v"))


def add_sound(soc: SoC, platform: Platform, hp: axi.AXIInterface, tap: bool = False, break_: str = "") -> None:
    """The audio core with its players on the sound CPU, both on `hp` (HP3); SOUND_WINDOW on the bus."""
    enable = soc.glass.cpu_run if hasattr(soc, "glass") else None
    pcm = _wb()
    soc.zm_audio = ZMAudio(platform, int(soc.sys_clk_freq), None, enable=enable, tap=tap, break_=break_, pcm_bus=pcm)
    soc.zm_snd = SoundCPU(platform, hp, soc.zm_audio.bus, pcm, enable)
    region = SoCRegion(origin=SOUND_WINDOW, size=SOUND_WINDOW_BYTES, cached=False)
    soc.bus.add_slave("zm_snd", soc.zm_snd.cart, region)
