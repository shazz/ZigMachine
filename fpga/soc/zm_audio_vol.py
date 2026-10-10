"""The master volume: the glass's REG_AUDIO_VOL applied to every mixed sample before HDMI.

The OSD's volume and mute (fpga/glass/src/config.zig) reached the register since glass 1.2.0,
but its output went nowhere: the PL played at unity whatever the menu said (2026-10-10). This
stage sits between the audio core's sample stream and zm_hdmi_out, in sys, one clock late:
gain = vol + vol[7] (0..256, so 255 is exactly unity), out = (sample * gain) >>> 8, 0 while
muted (glass/src/map.zig, "the master volume"). It exposes the same smp_valid/l/r as ZMAudio,
so hdmi_out takes either.
"""

from __future__ import annotations

from litex.gen import LiteXModule
from migen import If, Mux, Signal
from migen.fhdl.structure import _Value


def gain_of(audio_vol: Signal) -> _Value:
    """The 9-bit gain of a REG_AUDIO_VOL word {mute, volume[7:0]}: 0 when muted, else vol + vol[7]."""
    vol = audio_vol[:8]
    return Mux(audio_vol[8], 0, vol + vol[7])


class ZMAudioVolume(LiteXModule):
    def __init__(self, src: LiteXModule, audio_vol: Signal) -> None:
        """src: anything with smp_valid, smp_l, smp_r (ZMAudio)."""
        self.smp_valid, self.smp_l, self.smp_r = Signal(), Signal(16), Signal(16)
        gain = Signal(9)  # quasi-static (the ARM writes it, then a human listens): one flop
        self.sync += gain.eq(gain_of(audio_vol))
        gain_s = Signal((10, True))  # Migen multiplies signed only when both sides are
        self.comb += gain_s.eq(gain)
        for smp_in, smp_out in ((src.smp_l, self.smp_l), (src.smp_r, self.smp_r)):
            smp_s, prod = Signal((16, True)), Signal((26, True))
            self.comb += [smp_s.eq(smp_in), prod.eq(smp_s * gain_s)]
            self.sync += If(src.smp_valid, smp_out.eq(prod[8:24]))
        self.sync += self.smp_valid.eq(src.smp_valid)
