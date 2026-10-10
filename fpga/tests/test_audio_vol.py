"""The master volume stage (soc/zm_audio_vol.py) against map.zig's rule, in Migen's simulator."""

from __future__ import annotations

from collections.abc import Generator

from migen import Module, Signal, run_simulation

from soc.zm_audio_vol import ZMAudioVolume

MUTE = 1 << 8


class _Src(Module):
    def __init__(self) -> None:
        self.smp_valid, self.smp_l, self.smp_r = Signal(), Signal(16), Signal(16)


def _play(vol_word: int, left: int, right: int) -> tuple[int, int]:
    src, vol = _Src(), Signal(9)
    dut = ZMAudioVolume(src, vol)
    dut.submodules.src = src
    got: list[tuple[int, int]] = []

    def bench() -> Generator[object, None, None]:
        yield vol.eq(vol_word)
        yield  # the gain flop
        yield src.smp_l.eq(left & 0xFFFF)
        yield src.smp_r.eq(right & 0xFFFF)
        yield src.smp_valid.eq(1)
        yield
        yield src.smp_valid.eq(0)
        yield
        assert (yield dut.smp_valid) == 1 or got == []
        got.append(((yield dut.smp_l), (yield dut.smp_r)))

    run_simulation(dut, bench())
    signed = [v - 0x10000 if v & 0x8000 else v for v in got[0]]
    return signed[0], signed[1]


def test_volume_255_is_exactly_unity_for_both_signs() -> None:
    assert _play(255, 12345, -32768) == (12345, -32768)


def test_volume_scales_by_gain_over_256_and_rounds_toward_minus_infinity() -> None:
    assert _play(128, 1000, -1000) == (503, -504)  # vol 128 has bit 7 set: gain 129
    assert _play(64, 3, -3) == (0, -1)  # (3 * 64) >> 8 = 0, (-3 * 64) >>> 8 = -1


def test_mute_silences_whatever_the_volume() -> None:
    assert _play(MUTE | 255, 32767, -32768) == (0, 0)


def test_volume_zero_is_silence_without_mute() -> None:
    assert _play(0, 32767, -32768) == (0, 0)
