"""The PS DDR as the HP ports see it, for the board-memory sim (soc/hp_sim.py):
ONE 64-bit memory behind any number of AXI3 slave ports (HP0 for the CPU, HP1
for the video DMA).

- **The write channels as the board runs them: 32-bit** (`wr32`, AFI WRCHAN
  32BitEn = 1, fpga/boards/microphase_z7_7010/README.md). Only WDATA[31:0] and
  WSTRB[3:0] count, placed by the byte address; a 64-bit beat keeps its low
  word only, which is exactly the board's first picture (every odd pixel black).
- Each port takes one read burst and one write burst at a time. A read burst's
  first beat comes `latency` cycles after its AR (the HP path's first-beat
  cost, soc/zm_memtiming.py's `HP` figure); the rest stream a beat a cycle.
  Writes take their beats as they come and answer once the burst's last beat
  is in.
- The memory has one data path, as the DDR has: one beat a cycle over all
  ports, round robin when several want it.
- **Only the DDR window answers.** A burst outside DDR_BASE .. DDR_BASE +
  size reads `BAD` and writes nothing: a wrong address map in a bridge breaks
  the frame hash instead of aliasing into the right place.

The array is declared with a one-word init so the Verilog reads `<name>.init`
from the run directory at time 0 (one Verilated model, any firmware image):
64-bit words, little-endian, as cycles/video.mk writes main_ram.init.
"""

from __future__ import annotations

from litex.gen import LiteXModule
from litex.soc.interconnect import axi
from migen import Cat, If, Memory, Mux, Signal

from soc.zm_hp import DDR_BASE

BAD = 0xBADD_BADD_BADD_BADD


class ZMSimAXIRAM(LiteXModule):
    def __init__(
        self, size: int, ports: list[axi.AXIInterface], latency: int = 20, name: str = "zm_ddr", base: int = DDR_BASE,
        wr32: bool = False,
    ) -> None:
        depth = size // 8
        self.aw, self.base, self.wr32 = depth.bit_length() - 1, base, wr32
        assert base % size == 0, "the window must be aligned to its size"
        mem = Memory(64, depth, init=[0], name=name)
        self.port = mem.get_port(write_capable=True, we_granularity=8, async_read=True)
        self.specials += mem, self.port
        self.latency = latency
        self.error = Signal()  # sticky: a write burst whose WLAST disagreed with its AWLEN
        self.wants = [Signal(name=f"ddr_want{i}") for i in range(len(ports))]
        self.grants = [Signal(name=f"ddr_grant{i}") for i in range(len(ports))]
        for i, hp in enumerate(ports):
            self._slave(hp, self.wants[i], self.grants[i])
        self._arbiter()

    def _inside(self, addr: Signal) -> object:
        return addr[3 + self.aw :] == self.base >> (3 + self.aw)

    def _slave(self, hp: axi.AXIInterface, want: Signal, grant: Signal) -> None:
        """One port's read and write sides; `want`/`grant`: its turn on the memory."""
        r_on, r_ok, r_adr, r_left, r_wait = Signal(), Signal(), Signal(self.aw), Signal(5), Signal(8)
        w_on, w_ok, w_left, w_size = Signal(), Signal(), Signal(5), Signal(2)
        w_adr = Signal(self.aw + 3)  # a BYTE address: a 32-bit write channel moves by AxSIZE
        port = self.port
        w_go = w_on & hp.w.valid  # a write beat is waiting: it goes before this port's reads
        r_go = r_on & (r_wait == 0) & (~hp.r.valid | hp.r.ready) & ~w_go  # a read beat can load now
        self.comb += [
            hp.ar.ready.eq(~r_on), hp.aw.ready.eq(~w_on & ~hp.b.valid),
            want.eq(r_go | w_go), hp.w.ready.eq(grant & w_go),
            hp.r.resp.eq(0), hp.b.resp.eq(0), hp.r.id.eq(0), hp.b.id.eq(0),
            If(grant, port.adr.eq(r_adr),
               If(w_go, port.adr.eq(w_adr[3:]), *self._write_lanes(hp, w_adr, w_ok))),
        ]  # fmt: skip
        self.sync += [
            If(hp.ar.valid & hp.ar.ready,
               r_on.eq(1), r_ok.eq(self._inside(hp.ar.addr)), r_adr.eq(hp.ar.addr[3:]),
               r_left.eq(hp.ar.len + 1), r_wait.eq(self.latency)),
            If(r_wait != 0, r_wait.eq(r_wait - 1)),
            If(hp.r.valid & hp.r.ready, hp.r.valid.eq(0)),
            If(grant & r_go,
               hp.r.valid.eq(1), hp.r.data.eq(Mux(r_ok, port.dat_r, BAD)), hp.r.last.eq(r_left == 1),
               r_adr.eq(r_adr + 1), r_left.eq(r_left - 1), If(r_left == 1, r_on.eq(0))),
            # A burst the AFI would UPSIZE (wr32): on the board that path wrote twice the row
            # and wrong words. The model refuses it: the burst and every later write are lost.
            If(hp.aw.valid & hp.aw.ready & self._upsized(hp), self.error.eq(1)),
            If(hp.aw.valid & hp.aw.ready,
               w_on.eq(1), w_ok.eq(self._inside(hp.aw.addr) & ~self.error & ~self._upsized(hp)),
               w_adr.eq(hp.aw.addr),
               w_left.eq(hp.aw.len + 1), w_size.eq(hp.aw.size)),
            # The burst ends on its AWLEN beat count; a WLAST anywhere else is a protocol error
            # that poisons every later write (a real HP port would hang or misplace the data).
            If(hp.w.valid & hp.w.ready,
               w_adr.eq(w_adr + (1 << w_size)), w_left.eq(w_left - 1),
               If(hp.w.last != (w_left == 1), self.error.eq(1), w_ok.eq(0)),
               If(w_left == 1, w_on.eq(0), hp.b.valid.eq(1))),
            If(hp.b.valid & hp.b.ready, hp.b.valid.eq(0)),
        ]  # fmt: skip

    def _upsized(self, hp: axi.AXIInterface) -> object:
        """UG585 5.3.6: a 32-bit write channel upsizes an INCR burst of an even number of beats,
        64-bit aligned, when AWCACHE[1] is set."""
        if not self.wr32:
            return 0
        return hp.aw.cache[1] & hp.aw.len[0] & (hp.aw.addr[2] == 0) & (hp.aw.burst == 1)

    def _write_lanes(self, hp: axi.AXIInterface, w_adr: Signal, w_ok: Signal) -> list[object]:
        """What one W beat writes. 64-bit channel: the beat's lanes as strobed. 32-bit channel
        (AFI WRCHAN 32BitEn, `wr32`): only WDATA[31:0] / WSTRB[3:0], into the half of the word the
        byte address names; an 8-byte AxSIZE is "expanded" (UG585 5.3.6), so its upper half is lost."""
        port, strb = self.port, hp.w.strb
        if not self.wr32:
            return [port.dat_w.eq(hp.w.data), If(w_ok, port.we.eq(strb))]
        lo = hp.w.data[:32]
        return [port.dat_w.eq(Cat(lo, lo)), If(w_ok, port.we.eq(Mux(w_adr[2], strb[:4] << 4, strb[:4])))]

    def _arbiter(self) -> None:
        """Round robin: counting from the port after the last one served, the first that wants wins."""
        n, wants = len(self.wants), self.wants
        last = Signal(max=max(n, 2))
        for i in range(n):
            for k in range(n):  # last == k: the turn order is k+1, k+2, ...
                order = [(k + 1 + m) % n for m in range(n)]
                free = 1
                for j in order[: order.index(i)]:
                    free = free & ~wants[j]
                self.comb += If(last == k, self.grants[i].eq(wants[i] & free))
            self.sync += If(self.grants[i], last.eq(i))
