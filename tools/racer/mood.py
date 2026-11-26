"""A track's mood block (R82 M5 step 2): what the cart needs to show a track that is a FILE, not one it knows by index.

Header word 25 (byte 100, outside the CRC) is the block's offset, 0 = none (the oval's defaults below). The block is the
file's last, 32 bytes, inside the CRC:

    0 ground ramp u8 | 1 ground level u8 | 2 flags u8 | 3 backdrop u8          the far ground (palette index 4) and the strip
    4 sky top | 8 sky horizon | 12 backdrop far | 16 near | 20 skyline          RGB + a zero byte each (palette 12-14, the copper)
    24 clock start (s) | 25 clock extension a checkpoint (s)                   0 = computed from the line (M5 step 4: clock.zig)
    26 draw distance cap (tiles 3..8; 0 = the player's, R 8)                   M5 finish: a track too heavy at R 8 on the board
    27 haze RGB (3) | 30 haze start (x/256 of R) | 31 haze strength (x/255)      M6 (haze.zig); strength 0 = none, then 27..30 zero

flags bit 0 BENCH_ONLY: no racing line worth driving (the stress city): drive and race modes go back to the oval.
backdrop: the panorama strip's shape (apps/zig/scenes/racer/backdrop.zig, tools/racer/ref_sky.py): 0 hills, 1 docks, 2 peaks.
The cart refuses a block with a ramp past the palette, a level over 7, unknown flags, an unknown backdrop, a clock over
MAX_CLOCK, a draw distance cap outside 3..8 (but 0) or a haze colour or start without a strength.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field
from typing import Final

RGB = tuple[int, int, int]
SIZE: Final = 32
WORD: Final = 25
BENCH_ONLY: Final = 1
BACKDROPS: Final = ("hills", "docks", "peaks")
R_MIN, R_MAX = 3, 8  # the cart's draw distances (keys 3-8)
MAX_CLOCK: Final = (250, 60)  # the start and the extension, seconds (apps/zig/scenes/racer/trk.zig MAX_CLOCK)


@dataclass(frozen=True)
class Mood:
    ground_ramp: int = 1
    ground_level: int = 4
    flags: int = 0
    backdrop: int = 0
    sky: tuple[RGB, RGB] = ((28, 60, 150), (170, 205, 235))
    hills: tuple[RGB, RGB, RGB] = field(default=((110, 130, 170), (70, 100, 90), (60, 60, 90)))
    clock: tuple[int, int] = (0, 0)  # start, extension (s); 0 = the cart computes it from the racing line
    draw_r: int = 0  # the track's draw distance cap in tiles (3..8); 0 = none (the player's R)
    haze: RGB = (0, 0, 0)  # M6: the horizon haze's colour (apps/zig/scenes/racer/haze.zig)
    haze_start: int = 0  # where it starts, x/256 of the draw distance
    haze_strength: int = 0  # its blend at the draw distance, x/255; 0 = no haze

    def pack(self) -> bytes:
        if not (0 <= self.ground_level <= 7 and self.backdrop < len(BACKDROPS) and self.flags & ~BENCH_ONLY == 0):
            raise ValueError(f"mood {self}: level 0..7, backdrop < {len(BACKDROPS)}, flags {BENCH_ONLY} only")
        if not all(0 <= c <= m for c, m in zip(self.clock, MAX_CLOCK, strict=True)):
            raise ValueError(f"mood clock {self.clock}: start 0..{MAX_CLOCK[0]} s, extension 0..{MAX_CLOCK[1]} s")
        if self.draw_r != 0 and not R_MIN <= self.draw_r <= R_MAX:
            raise ValueError(f"mood draw distance cap {self.draw_r}: 0 (none) or {R_MIN}..{R_MAX} tiles")
        rgbs = (*self.sky, *self.hills, self.haze)
        if any(not 0 <= c <= 255 for rgb in rgbs for c in rgb) or not 0 <= self.haze_start <= 255 or not 0 <= self.haze_strength <= 255:
            raise ValueError(f"mood colours {rgbs}, haze start {self.haze_start}, strength {self.haze_strength}: ints 0..255")
        if self.haze_strength == 0 and (self.haze_start != 0 or any(self.haze)):
            raise ValueError(f"mood haze {self.haze} start {self.haze_start} without a strength (0 = no haze)")
        head = struct.pack("<4B", self.ground_ramp, self.ground_level, self.flags, self.backdrop)
        tail = bytes(self.clock) + bytes([self.draw_r]) + bytes(self.haze) + bytes([self.haze_start, self.haze_strength])
        return head + b"".join(bytes(rgb) + b"\0" for rgb in rgbs[:5]) + tail


def unpack(blob: bytes) -> Mood:
    """The mood of a converted track (the defaults when it has no block)."""
    at = struct.unpack_from("<I", blob, 4 * WORD)[0]
    if at == 0:
        return Mood()
    b = blob[at:at + SIZE]
    rgb = [(b[4 + 4 * k], b[5 + 4 * k], b[6 + 4 * k]) for k in range(5)]
    return Mood(b[0], b[1], b[2], b[3], (rgb[0], rgb[1]), (rgb[2], rgb[3], rgb[4]), (b[24], b[25]), b[26], (b[27], b[28], b[29]), b[30], b[31])


CAR_RAMPS: Final = range(12, 19)  # the cars' ramps (carmodel.zig: body, dark, glass, the 4 liveries): never hazed entries


def haze_room(blob: bytes) -> tuple[int, int]:
    """(the track's most distinct face colours in any one shading, the haze pool's entries): the cart hazes a track only when
    the first fits the second (apps/zig/scenes/racer/haze.zig: the pool is the entries past the track's and the cars' ramps,
    16 + 8 x max(ramps, 19); it is built for the shading in force, key i's FLAT / LIT / SOFT)."""
    w = struct.unpack_from("<32I", blob, 0)
    lo = min(256, 16 + 8 * max(w[9], 19))
    shades: list[set[int]] = [set(), set(), set()]
    for n, at in ((w[5], w[14]), (w[6], w[15])):
        for i in range(n):
            c, alt = blob[at + 32 * i + 10], struct.unpack_from("<I", blob, at + 32 * i + 28)[0]
            for s, cs in enumerate(shades):
                cs.add(c if s == 0 or alt == 0 else (alt >> (8 * (s - 1))) & 0xFF)
    most = max(len({c for c in cs if 16 <= c < lo and (c - 16) // 8 not in CAR_RAMPS}) for cs in shades)
    return most, 256 - lo
