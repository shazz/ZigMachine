"""The sound CPU's glue in Migen's simulator: its register block (soc/zm_sound_regs.py),
which each CPU may only write on its own side, and the audio core's PCM byte port as a
Wishbone read (soc/zm_audio_soc.py PcmWB). The whole path, a song played on the sound CPU
into the core, is `make snd-bench` on the soc_hp_snd model."""

from __future__ import annotations

from collections.abc import Generator

from litex.soc.interconnect import wishbone
from migen import Module, Signal, run_simulation

from soc.zm_audio_soc import PcmWB
from soc.zm_hp import CPU_BASE, WishboneHP, hp_interface
from soc.zm_simaxi import ZMSimAXIRAM
from soc.zm_sound_regs import CTRL, ID, REG_ID, SoundRegs

Sim = Generator[object, None, None]
S2C = 32


def _wb() -> wishbone.Interface:
    return wishbone.Interface(data_width=32, address_width=32, addressing="word")


class Regs(Module):
    def __init__(self) -> None:
        self.cart, self.snd, self.ibus, self.dbus = _wb(), _wb(), _wb(), _wb()
        self.submodules.regs = SoundRegs(self.cart, self.snd, self.ibus, self.dbus)


def access(bus: wishbone.Interface, word: int, value: int | None = None) -> Sim:
    yield bus.adr.eq(word)
    yield bus.we.eq(value is not None)
    yield bus.dat_w.eq(value or 0)
    yield bus.sel.eq(0xF)
    yield bus.cyc.eq(1)
    yield bus.stb.eq(1)
    yield
    while not (yield bus.ack):
        yield
    data = yield bus.dat_r
    yield bus.cyc.eq(0)
    yield bus.stb.eq(0)
    yield
    return data


def test_each_cpu_writes_only_its_own_bank_and_both_read_both() -> None:
    r, got = Regs(), {}

    def bench() -> Sim:
        yield from access(r.cart, 3, 0xCA57)  # C2S[3]: the cart's
        yield from access(r.snd, S2C + 3, 0x50D)  # S2C[3]: the sound CPU's
        yield from access(r.snd, 3, 0xBAD)  # the sound CPU on the cart's bank: ignored
        yield from access(r.cart, S2C + 3, 0xBAD)  # and the reverse
        got["c2s_from_snd"] = yield from access(r.snd, 3)
        got["s2c_from_cart"] = yield from access(r.cart, S2C + 3)
        got["c2s_from_cart"] = yield from access(r.cart, 3)

    run_simulation(r, [bench()])
    assert got == {"c2s_from_snd": 0xCA57, "s2c_from_cart": 0x50D, "c2s_from_cart": 0xCA57}


def test_run_is_the_carts_to_set_and_the_id_answers() -> None:
    r, got = Regs(), {}

    def bench() -> Sim:
        got["reset"] = yield r.regs.run
        yield from access(r.snd, CTRL, 1)  # the sound CPU cannot start itself
        got["by_snd"] = yield r.regs.run
        yield from access(r.cart, CTRL, 1)
        got["by_cart"] = yield r.regs.run
        got["read"] = yield from access(r.snd, CTRL)
        got["id"] = yield from access(r.cart, REG_ID)

    run_simulation(r, [bench()])
    assert got == {"reset": 0, "by_snd": 0, "by_cart": 1, "read": 1, "id": ID}


class Pcm(Module):
    def __init__(self, base: int) -> None:
        self.bus, self.hp = _wb(), hp_interface()
        self.submodules.port = PcmWB(self.bus, Signal(32, reset=base))
        self.submodules.bridge = WishboneHP(self.bus, self.hp)
        self.submodules.ram = ZMSimAXIRAM(1 << 16, [self.hp], latency=6, wr32=True)


def test_pcm_bytes_come_back_lane_by_lane_from_the_base_plus_offset() -> None:
    base = CPU_BASE + 0x1000
    p, got = Pcm(base), []
    mem = next(x for x in p.ram._fragment.specials if hasattr(x, "depth"))  # the model's Memory
    mem.init = [0] * mem.depth
    mem.init[(0x1000 + 0x20) // 8] = 0x8877665544332211

    def bench() -> Sim:
        for off in (0x20, 0x21, 0x23, 0x26):
            yield p.port.addr.eq(off)
            yield p.port.req.eq(1)
            yield
            while not (yield p.port.ack):
                yield
            got.append((yield p.port.data))
            yield p.port.req.eq(0)
            yield

    run_simulation(p, [bench()])
    assert got == [0x11, 0x22, 0x44, 0x77]
