"""Kestrel Racing's ARCADE longitudinal model (the "32X feel", R82): our own engine curves and their integer twin.

The cart's `racer/arcade.zig` steps a car's forward speed with these numbers; this file is the oracle: the same integer
arithmetic in Python (`step`), the per-class parameter blocks in human units (`CLASSES`, fitted by feel_fit.py to times
measured from the 32X and kept locally: no 32X table is in here, only our own control points), and the generated Zig
block (`emit`, apps/zig/scenes/racer/feel_params.zig) with the straight-line pins the native test checks.

The model, per 30 Hz tick, on the forward speed s (16.16 units a tick; km/h = 900 s):
    net(s)   our full-throttle acceleration: a piecewise-linear curve through a few (km/h, km/h a second) points, 0 at top
    drag(s)  our coast-down deceleration, the same kind of curve; the engine's tractive part is net + drag
    a = thr * (net + drag) - drag - off * K_OFF * s^2 - brake * BRAKE,  then a >= -MAX_DEC
s' = clamp(s + a, 0, max(s, top)). thr and brake are pedals 0..256 ramping by PEDAL a tick; off is 0, 1/2 (one or two
wheels off the asphalt) or 1 (three or four). Accelerations are Q24 a tick, rounded once into the Q16 speed.

    python3 tools/racer/feel.py           # (re)write feel_params.zig
    python3 tools/racer/feel.py --check   # exit 1 if it is not what this file writes
"""

from __future__ import annotations

import argparse
import sys
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Final

HZ: Final = 30
KMH: Final = 900  # km/h per (unit a tick): freds72's speedometer, racehud.zig
PEDAL: Final = 32  # pedal ramp a tick (0..256): full in 8 ticks, a quarter second
OUT: Final = Path(__file__).resolve().parents[2] / "apps/zig/scenes/racer/feel_params.zig"
OFF_NONE, OFF_HALF, OFF_FULL = 0, 1, 2


@dataclass(frozen=True)
class Klass:
    """One car class in human units: control points (km/h, km/h a second), the off-road and brake constants."""

    name: str
    top: int  # km/h: where net reaches 0
    net: tuple[tuple[int, float], ...]  # full-throttle acceleration (km/h, km/h/s), the last point at `top`, 0
    drag: tuple[tuple[int, float], ...]  # coast-down deceleration (km/h, km/h/s)
    off: float  # off-road drag at 100 km/h, km/h/s (it grows with the square of speed)
    brake: float = 120.0  # km/h/s at a full brake pedal
    max_dec: float = 140.0  # km/h/s: no deceleration is harder (a wall, the off-road wall of drag at speed)


# Fitted by feel_fit.py (method and residuals in docs/ports/kestrel_racing/FEEL.md). Our numbers.
CLASSES: Final = (
    Klass("FORMULA", 330, ((0, 60.0), (100, 56.25), (200, 44.0), (280, 20.75), (330, 0.0)),
          ((0, 0.5), (165, 9.25), (330, 65.25)), 25.5),
    Klass("STOCK", 285, ((0, 65.0), (100, 45.0), (200, 28.0), (260, 28.0), (285, 0.0)),
          ((0, 1.25), (145, 7.5), (285, 45.25)), 19.25),
    Klass("PROTO", 380, ((0, 59.75), (100, 38.25), (200, 27.0), (330, 17.0), (380, 0.0)),
          ((0, 1.25), (190, 9.0), (380, 54.25)), 17.25),
)


def q16(kmh: float) -> int:
    return round(kmh / KMH * 65536)


def q24(kmh_s: float) -> int:
    return round(kmh_s / KMH / HZ * (1 << 24))


@dataclass(frozen=True)
class Curve:
    """A piecewise-linear Q24 curve over Q16 speed: points and the slope (Q16) of each span."""

    s: tuple[int, ...]
    a: tuple[int, ...]
    m: tuple[int, ...]

    @staticmethod
    def of(pts: tuple[tuple[int, float], ...]) -> Curve:
        s = tuple(q16(k) for k, _ in pts)
        a = tuple(q24(v) for _, v in pts)
        if any(b <= x for x, b in zip(s, s[1:], strict=False)):
            raise ValueError("curve speeds must rise")
        m = tuple(((a[i + 1] - a[i]) << 16) // (s[i + 1] - s[i]) for i in range(len(s) - 1))
        return Curve(s, a, m)

    def at(self, v: int) -> int:
        """The curve at speed v: flat beyond its ends."""
        if v <= self.s[0]:
            return self.a[0]
        for i in range(len(self.m)):
            if v < self.s[i + 1]:
                return self.a[i] + (((v - self.s[i]) * self.m[i]) >> 16)
        return self.a[-1]


@dataclass(frozen=True)
class Block:
    """A class in the cart's integers (what feel_params.zig holds)."""

    top: int
    net: Curve
    drag: Curve
    k_off: int  # Q16: off-road Q24 drag = (s^2 >> 16) * k_off >> 16
    brake: int
    max_dec: int

    @staticmethod
    def of(k: Klass) -> Block:
        if k.net[-1] != (k.top, 0.0):
            raise ValueError(f"{k.name}: the net curve must end at (top, 0)")
        s100 = q16(100)
        return Block(q16(k.top), Curve.of(k.net), Curve.of(k.drag), round(q24(k.off) * 65536 / ((s100 * s100) >> 16)),
                     q24(k.brake), q24(k.max_dec))


def step(b: Block, s: int, thr: int, brake: int, off: int) -> int:
    """One tick of forward speed (Q16), as arcade.zig's `speed`."""
    drag = b.drag.at(s)
    tract = (b.net.at(s) if s < b.top else 0) + drag
    a = ((tract * thr) >> 8) - drag - ((b.brake * brake) >> 8)
    if off != OFF_NONE:
        a -= ((((s * s) >> 16) * b.k_off) >> 16) >> (1 if off == OFF_HALF else 0)
    a = max(a, -b.max_dec)
    return min(max(s + ((a + 128) >> 8), 0), max(s, b.top))


def pedal(p: int, held: bool) -> int:
    return min(p + PEDAL, 256) if held else max(p - PEDAL, 0)


def run(b: Block, ticks: int, s0: int = 0, held: bool = True, off: int = OFF_NONE) -> list[int]:
    """Speed after each tick from s0 with the throttle held (ramping from 0) or released."""
    s, thr, out = s0, 0, []
    for _ in range(ticks):
        thr = pedal(thr, held)
        s = step(b, s, thr, 0, off)
        out.append(s)
    return out


def ticks_to(trace: list[int], kmh: int) -> int:
    """The first tick (1-based) the trace reaches kmh, or 0."""
    return next((i + 1 for i, s in enumerate(trace) if s * KMH >= kmh << 16), 0)


PIN_TICKS: Final = 600


def pins(b: Block) -> tuple[int, int, int, int]:
    """The native test's pins: ticks to 100 and 200 km/h, the full-throttle run's CRC, the coast-down's CRC."""
    up = run(b, PIN_TICKS)
    down = run(b, PIN_TICKS, b.top, held=False)
    crc = lambda t: zlib.crc32(b"".join(v.to_bytes(4, "little", signed=True) for v in t))  # noqa: E731
    return ticks_to(up, 100), ticks_to(up, 200), crc(up), crc(down)


def _curve(c: Curve) -> str:
    return f".{{ .s = .{{ {', '.join(map(str, c.s))} }}, .a = .{{ {', '.join(map(str, c.a))} }}, " \
           f".m = .{{ {', '.join(map(str, c.m))} }} }}"


def emit() -> str:
    lines = ["// GENERATED by tools/racer/feel.py (our fitted curves; method: docs/ports/kestrel_racing/FEEL.md). Do not edit.",
             "pub const Curve = struct { s: [5]i32, a: [5]i32, m: [4]i32 };",
             "pub const Drag = struct { s: [3]i32, a: [3]i32, m: [2]i32 };",
             "pub const Block = struct { name: []const u8, top: i32, net: Curve, drag: Drag, k_off: i32, brake: i32, max_dec: i32 };",
             "pub const Pins = struct { to100: u32, to200: u32, up: u32, down: u32 };",
             f"pub const PIN_TICKS = {PIN_TICKS};", "pub const CLASSES = [_]Block{"]
    for k in CLASSES:
        b = Block.of(k)
        lines.append(f'    .{{ .name = "{k.name}", .top = {b.top}, .net = {_curve(b.net)}, .drag = {_curve(b.drag)}, '
                     f".k_off = {b.k_off}, .brake = {b.brake}, .max_dec = {b.max_dec} }},")
    lines.append("};")
    lines.append("pub const PINS = [_]Pins{")
    for k in CLASSES:
        p = pins(Block.of(k))
        lines.append(f"    .{{ .to100 = {p[0]}, .to200 = {p[1]}, .up = 0x{p[2]:08x}, .down = 0x{p[3]:08x} }},")
    lines.append("};")
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--check", action="store_true")
    a = ap.parse_args(argv)
    text = emit()
    if a.check:
        if not OUT.exists() or OUT.read_text() != text:
            print(f"feel: {OUT} is stale: run tools/racer/feel.py", file=sys.stderr)
            return 1
        return 0
    OUT.write_text(text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
