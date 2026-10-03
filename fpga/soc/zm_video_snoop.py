"""How the cart's stores to the machine's video region reach the compositor
(Fable #6, rtl/video/README.md "The video region").

The region stays ordinary memory, in DDR, at its place in the cart's linear
memory (HW_VIDEO_BASE): every load the cart or the ROM makes reads what the
wasm machine would, unimplemented registers included, because it IS the
machine's memory. The compositor keeps its own copy of the words it reads (the
register block, the 4 palettes, the BEAM table) and learns of every change by
SNOOPING the CPU's stores: the D-cache is write-through, so each store crosses
the bus. Stores to the framebuffers are not snooped; the compositor reads those
from memory.

A snooped store reaches the compositor when it leaves the CPU's posted-write
buffer, not when the CPU retires it: an entry leaves every `drain` cycles
(soc/zm_memtiming.py's sb_drain, the HP port's write rate). `empty` says none
is still on its way; the sequencer waits for it (and for the store buffer
itself) before every pass. That is the drain rule of Fable #5.

In the sims the snoop sits on the main-RAM path and holds a store back when its
queue is full; on the board until the HP bridge exists it taps the CPU's data
bus (`slave` = None) and delivers every cycle.
"""

from __future__ import annotations

from typing import Any

from litex.gen import LiteXModule
from migen import Array, Cat, If, Mux, Signal

from gen import memmap as mm

# A LiteX wishbone.Interface: untyped, its signals are attributes made at runtime.
Bus = Any
DEPTH = 16
REG_WORDS, PAL_W0 = 32, mm.OFF_PAL // 4  # the register block the compositor decodes; the palettes
REGS_PALS_WORDS = mm.OFF_VRAM // 4  # the register block and the palettes: words 0 .. OFF_VRAM / 4
BEAM_W0, BEAM_WORDS = mm.OFF_BEAM_TABLE // 4, mm.BEAM_MAX


class ZMVideoSnoop(LiteXModule):
    def __init__(self, master: Bus, slave: Bus | None, vbase: Signal, drain: Signal) -> None:
        """master/slave: a 32-bit word-addressed path to main RAM; vbase: the bus byte
        address of HW_VIDEO_BASE; drain: cycles per delivered store (0 or 1: every cycle)."""
        self.we, self.waddr, self.be, self.wdata = Signal(), Signal(21), Signal(4), Signal(32)
        self.sel = Signal(3)  # {beam table, palettes, register block}
        self.empty = Signal()
        # The tap is pipelined: register the bus, then the window offset, then
        # compare. On the board the CPU's data bus -> subtract -> compare -> queue
        # path was the critical one (79 MHz; 84 with one stage, 97 with all three).
        t_store, t_adr, t_sel, t_dat = Signal(), Signal(30), Signal(4), Signal(32)
        o_store, off, o_sel, o_dat = Signal(), Signal(32), Signal(4), Signal(32)
        self.sync += [
            t_store.eq(master.cyc & master.stb & master.we & master.ack),
            t_adr.eq(master.adr),
            t_sel.eq(master.sel),
            t_dat.eq(master.dat_w),
            o_store.eq(t_store),
            off.eq(t_adr - vbase[2:]),
            o_sel.eq(t_sel),
            o_dat.eq(t_dat),
        ]
        # The compositor's decode, done here so its write port takes ready-made
        # selects ({beam, pal, reg}) and compares nothing (TIMING_FABLE P1-4).
        sel = Signal(3)
        self.comb += sel.eq(
            Cat(
                off < REG_WORDS,
                (off >= PAL_W0) & (off < REGS_PALS_WORDS),
                (off >= BEAM_W0) & (off < BEAM_W0 + BEAM_WORDS),
            )
        )
        snooped = sel != 0
        self.fifo = fifo = _Queue(60, DEPTH)
        if slave is not None:  # the sims: hold any store back while the queue (+ the tap) could overflow
            self.comb += master.connect(slave, omit={"stb"})
            room = fifo.level + t_store + o_store < DEPTH - 1  # queued + in the tap + this one
            self.comb += slave.stb.eq(master.stb & ~(master.we & ~room))
        self.comb += [
            fifo.we.eq(o_store & snooped),
            fifo.din.eq(Cat(off[:21], o_sel, o_dat, sel)),
        ]
        # A store still in the tap's two stages is on its way too.
        self.tap_busy = t_store | o_store
        self._deliver(drain)

    def _deliver(self, drain: Signal) -> None:
        """One queued store to the compositor's CPU port every `drain` cycles, from a
        register (the queue's read mux and the compositor's decode were the next
        critical path once the tap was registered)."""
        fifo, wait = self.fifo, Signal(16)
        due = wait + 1 >= drain
        pop = fifo.readable & due
        self.comb += [
            fifo.re.eq(due),
            self.empty.eq(~fifo.readable & ~self.tap_busy & ~self.we),
        ]
        self.sync += [
            If(pop, wait.eq(0)).Elif(fifo.readable, wait.eq(wait + 1)),
            self.we.eq(pop),
            Cat(self.waddr, self.be, self.wdata, self.sel).eq(fifo.dout),
        ]


class _Queue(LiteXModule):
    """A small FIFO in flip-flops (no RAM: 16 entries; and Migen's simulator cannot
    run the pinned migen's write-only FIFO memory ports)."""

    def __init__(self, width: int, depth: int) -> None:
        self.we, self.din, self.writable = Signal(), Signal(width), Signal()
        self.re, self.dout, self.readable = Signal(), Signal(width), Signal()
        slots = Array(Signal(width) for _ in range(depth))
        head, tail, level = Signal(max=depth), Signal(max=depth), Signal(max=depth + 1)
        self.level = level
        push, pop = Signal(), Signal()
        self.comb += [
            self.writable.eq(level != depth),
            self.readable.eq(level != 0),
            self.dout.eq(slots[head]),
            push.eq(self.we & self.writable),
            pop.eq(self.re & self.readable),
        ]
        self.sync += [
            If(push, slots[tail].eq(self.din), tail.eq(Mux(tail == depth - 1, 0, tail + 1))),
            If(pop, head.eq(Mux(head == depth - 1, 0, head + 1))),
            level.eq(level + push - pop),
        ]


def attach_snoop(video: Any, snoop: ZMVideoSnoop) -> list[Any]:
    """The statements that feed `snoop` into a ZMVideo (soc/zm_video_pipe.py)."""
    return [
        video.snoop_we.eq(snoop.we),
        video.snoop_waddr.eq(snoop.waddr),
        video.snoop_be.eq(snoop.be),
        video.snoop_wdata.eq(snoop.wdata),
        video.snoop_sel.eq(snoop.sel),
    ]
