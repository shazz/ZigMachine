"""The compositor's clock crossings (soc/zm_cdc.py, soc/zm_video_cdc.py) in Migen's
simulator, with `sys` and `comp` at unrelated periods (10 and 7 units)."""

from __future__ import annotations

from collections.abc import Generator

from migen import If, Module, Signal, run_simulation

from soc.zm_cdc import AsyncQueue, ReqCross
from soc.zm_video_cdc import WritePortCross, ZMVideoCDC
from soc.zm_video_dma import ZMVideoDMA, read_port, write_port

Sim = Generator[object, None, None]
CLOCKS = {"sys": 10, "comp": 7}


def _cycles(n: int) -> Sim:
    for _ in range(n):
        yield


def test_queue_delivers_every_word_in_order_across_the_clocks() -> None:
    q, got, want = AsyncQueue(16, 4, "sys", "comp"), [], list(range(1, 40))

    # A generator's writes land at the next clock, so each side decides from what
    # this clock holds: a word moves when its strobe and the queue's flag are both up now.
    def writer() -> Sim:
        i = 0
        while i < len(want):
            if (yield q.we) and (yield q.writable):
                i += 1
            if i < len(want):
                yield q.din.eq(want[i])
            yield q.we.eq(i < len(want))
            yield

    def reader() -> Sim:
        for i in range(600):
            if (yield q.re) and (yield q.readable):
                got.append((yield q.dout))
            yield q.re.eq((i // 25) % 2)  # stop reading now and then, so the queue fills
            yield

    run_simulation(q, {"sys": writer(), "comp": reader()}, clocks=CLOCKS)
    assert got == want


def test_queue_full_refuses_and_empty_waits_for_the_reader() -> None:
    q, seen = AsyncQueue(8, 4, "sys", "comp"), {}

    def writer() -> Sim:
        yield q.we.eq(1)
        for v in range(6):  # two more than fit; nobody reads
            yield q.din.eq(v)
            yield
        yield q.we.eq(0)
        yield from _cycles(4)
        seen["full_writable"], seen["full_level"] = (yield q.writable), (yield q.level_w)
        while not (yield q.empty_w):
            yield
        seen["drained"] = True

    def reader() -> Sim:
        yield from _cycles(80)
        yield q.re.eq(1)
        yield from _cycles(40)

    run_simulation(q, {"sys": writer(), "comp": reader()}, clocks=CLOCKS)
    assert seen == {"full_writable": 0, "full_level": 4, "drained": True}


def test_request_payload_crosses_intact_one_at_a_time() -> None:
    x, got, taken = ReqCross(12, "comp", "sys"), [], []

    def source() -> Sim:
        for v in (0xABC, 0x123):
            yield x.s_valid.eq(1)
            yield x.s_payload.eq(v)
            yield
            while not (yield x.s_ready):
                yield
            taken.append(v)
            yield x.s_valid.eq(0)
            yield x.s_payload.eq(0xFFF)  # the latched payload must not follow the source's bus
            yield

    def dest() -> Sim:
        for _ in range(120):
            if (yield x.d_valid):
                got.append((yield x.d_payload))
                yield x.d_ready.eq(1)
                yield
                yield x.d_ready.eq(0)
            yield

    run_simulation(x, {"comp": source(), "sys": dest()}, clocks=CLOCKS)
    assert (taken, got) == ([0xABC, 0x123], [0xABC, 0x123])


class CmdBench(Module):
    """The command echo against a compositor that is busy `work` clocks a command."""

    def __init__(self, work: int) -> None:
        names = ("cmd_valid", "cmd_ready", "painted", "pass_done", "overflow", "underrun", "vbl", "front", "pending")
        self.p = p = {n: Signal(name=n) for n in names} | {"swaps": Signal(32)}
        self.submodules.x = ZMVideoCDC(p, "comp")
        left = Signal(8)
        self.comb += p["cmd_ready"].eq(left == 0)
        self.sync.comp += [
            p["painted"].eq(left == 2),
            If(p["cmd_valid"] & p["cmd_ready"], left.eq(work)).Elif(left != 0, left.eq(left - 1)),
        ]


def test_command_is_not_ready_until_the_compositor_finished_it() -> None:
    bench, trace = CmdBench(work=30), []

    def seq() -> Sim:
        yield from _cycles(10)
        trace.append(("before", (yield bench.x.ready), (yield bench.x.painted)))
        yield bench.x.cmd_re.eq(1)
        yield
        yield bench.x.cmd_re.eq(0)
        yield
        trace.append(("after", (yield bench.x.ready), (yield bench.x.painted)))
        n = 0
        while not (yield bench.x.painted):
            n += 1
            yield
        trace.append(("painted", (yield bench.x.ready), n > 10))
        while not (yield bench.x.ready):
            yield
        trace.append(("ready", 1, (yield bench.x.painted)))

    run_simulation(bench, {"sys": seq(), "comp": _cycles(200)}, clocks=CLOCKS)
    assert trace == [("before", 1, 0), ("after", 0, 0), ("painted", 0, True), ("ready", 1, 1)]


class WriteBench(Module):
    """The RTL's write port in comp, crossed onto the DMA in sys and a slow memory."""

    def __init__(self) -> None:
        self.c, s, sc = write_port("c"), write_port("s"), read_port("sc")
        self.submodules.x = WritePortCross(self.c, s, "comp")
        self.submodules.dma = ZMVideoDMA([sc], s)
        bus, self.mem, wait = self.dma.bus, [], Signal(2)
        self.sync += wait.eq(wait + 1)
        self.comb += bus.ack.eq(bus.cyc & bus.stb & (wait == 0))  # a beat every 4 clocks


def test_write_stays_busy_until_the_dma_has_written_the_last_beat() -> None:
    bench, log = WriteBench(), {}
    c, bus = bench.c, bench.dma.bus

    def rtl() -> Sim:
        yield from (s.eq(v) for s, v in ((c.req_addr, 0x100), (c.req_len, 4), (c.req_valid, 1)))
        while not ((yield c.req_valid) and (yield c.req_ready)):
            yield
        yield c.req_valid.eq(0)
        beats = 0
        while beats < 4:
            if (yield c.dat_valid) and (yield c.dat_ready):
                beats += 1
            yield c.dat.eq(0xD0 + beats)
            yield c.dat_valid.eq(beats < 4)
            yield
        log["busy_after_push"] = yield c.busy
        while (yield c.busy):
            yield
        log["idle_after"] = len(bench.mem)

    def memory() -> Sim:
        for _ in range(300):
            if (yield bus.cyc) and (yield bus.stb) and (yield bus.ack):
                bench.mem.append(((yield bus.adr), (yield bus.dat_w)))
            yield

    run_simulation(bench, {"comp": rtl(), "sys": memory()}, clocks=CLOCKS)
    assert log == {"busy_after_push": 1, "idle_after": 4}
    assert bench.mem == [(0x20 + i, 0xD0 + i) for i in range(4)]
