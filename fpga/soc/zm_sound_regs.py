"""The sound CPU's register block (docs/FPGA_SOUND_CPU.md "Registers"), seen by both CPUs
at SOUND_WINDOW: two 32-word mailbox banks, the sound CPU's run bit, its counters, and a
console for the sim.

| Word | Name | Cart CPU | Sound CPU |
|---|---|---|---|
| 0-31 | C2S[0..31] | RW | R | commands, cart to sound (cycles/snd_mailbox.h) |
| 32-63 | S2C[0..31] | R | RW | answers and counters, sound to cart |
| 64 | CTRL | RW | R | bit 0 RUN: the sound CPU leaves reset (its image is in DDR) |
| 65 | CYCLES | R | R | sys clocks since reset |
| 66 | IBUS_WAIT | R | R | sys clocks the sound CPU's I-bus waited, since it left reset |
| 67 | DBUS_WAIT | R | R | the same for its D-bus |
| 68 | PUTC | - | W | a character to the sim's console (`$write`); nothing on the board |
| 69 | ID | R | R | 0x5A4D5343 'ZMSC' |

Each bank has one writer, so a word never has two masters; a reader sees a word whole
(32-bit stores). Bank words are LUTRAM (one write port, an async read port per side).
"""

from __future__ import annotations

from typing import Any

from litex.gen import LiteXModule
from migen import Case, If, Memory, Mux, Signal

ID = 0x5A4D5343  # 'ZMSC'
BANK = 32
CTRL, CYCLES, IBUS_WAIT, DBUS_WAIT, PUTC, REG_ID = 64, 65, 66, 67, 68, 69

# LiteX wishbone.Interface: untyped, its signals are attributes made at runtime.
Bus = Any


def _word(bus: Bus) -> Any:  # Any: a Migen slice
    return bus.adr[:7]  # 128 words: the banks, then the registers


class SoundRegs(LiteXModule):
    """`cart`, `snd`: word-addressed Wishbone slaves; `ibus`, `dbus`: the sound CPU's buses
    (counted); `run`: CTRL.RUN."""

    def __init__(self, cart: Bus, snd: Bus, ibus: Bus, dbus: Bus) -> None:
        self.run = Signal()
        c2s, s2c = Memory(32, BANK, name="snd_c2s"), Memory(32, BANK, name="snd_s2c")
        c2s_w, s2c_w = c2s.get_port(write_capable=True), s2c.get_port(write_capable=True)
        ports = {(m, side): m.get_port(async_read=True) for m in (c2s, s2c) for side in ("cart", "snd")}
        self.specials += c2s, s2c, c2s_w, s2c_w, *ports.values()
        cycles, iwait, dwait = Signal(32), Signal(32), Signal(32)
        self.sync += [
            cycles.eq(cycles + 1),
            If(ibus.cyc & ibus.stb & ~ibus.ack, iwait.eq(iwait + 1)),
            If(dbus.cyc & dbus.stb & ~dbus.ack, dwait.eq(dwait + 1)),
        ]
        regs = {CYCLES: cycles, IBUS_WAIT: iwait, DBUS_WAIT: dwait, REG_ID: ID}
        for side, bus, own_w in (("cart", cart, c2s_w), ("snd", snd, s2c_w)):
            self._port(bus, own_w, ports[(c2s, side)], ports[(s2c, side)], regs, side == "cart")
        self._console(snd)

    def _port(self, bus: Bus, own_w: Any, c2s_r: Any, s2c_r: Any, regs: dict[int, Any], cart: bool) -> None:
        """One side: writes to its own bank (and CTRL, from the cart); reads of everything."""
        w, stb = _word(bus), bus.cyc & bus.stb & ~bus.ack
        bank_w = (w[5:] == (0 if cart else 1)) & ~w[6]
        rd = Signal(32)
        self.comb += [
            own_w.adr.eq(w[:5]), own_w.dat_w.eq(bus.dat_w), own_w.we.eq(stb & bus.we & bank_w),
            c2s_r.adr.eq(w[:5]), s2c_r.adr.eq(w[:5]),
        ]  # fmt: skip
        cases = {reg: rd.eq(v) for reg, v in regs.items()}
        cases[CTRL] = rd.eq(self.run)
        cases["default"] = rd.eq(Mux(w[5], s2c_r.dat_r, c2s_r.dat_r))
        self.comb += Case(w, cases)
        self.sync += [bus.ack.eq(stb), bus.dat_r.eq(rd)]
        if cart:
            self.sync += If(stb & bus.we & (w == CTRL), self.run.eq(bus.dat_w[0]))

    def _console(self, snd: Bus) -> None:
        """PUTC as `putc`/`char`: SoundCPU hands them to the sim's console (rtl/sim/zm_snd_putc.v)."""
        self.putc, self.char = Signal(), Signal(8)
        self.comb += [
            self.putc.eq(snd.cyc & snd.stb & ~snd.ack & snd.we & (_word(snd) == PUTC)),
            self.char.eq(snd.dat_w[:8]),
        ]
