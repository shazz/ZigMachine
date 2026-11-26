"""A track's mood block (R82 M5 step 2): what the cart needs to show a track that is a FILE, not one it knows by index.

Header word 25 (byte 100, outside the CRC) is the block's offset, 0 = none (the oval's defaults below). The block is the
file's last, 32 bytes, inside the CRC:

    0 ground ramp u8 | 1 ground level u8 | 2 flags u8 | 3 backdrop u8          the far ground (palette index 4) and the strip
    4 sky top | 8 sky horizon | 12 backdrop far | 16 near | 20 skyline          RGB + a zero byte each (palette 12-14, the copper)
    24 clock start (s) | 25 clock extension a checkpoint (s)                   0 = computed from the line (M5 step 4: clock.zig)
    26 draw distance cap (tiles 3..8; 0 = the player's, R 8)                   M5 finish: a track too heavy at R 8 on the board
    27..31 zero

flags bit 0 BENCH_ONLY: no racing line worth driving (the stress city): drive and race modes go back to the oval.
backdrop: the panorama strip's shape (apps/zig/scenes/racer/backdrop.zig, tools/racer/ref_sky.py): 0 hills, 1 docks, 2 peaks.
The cart refuses a block with a ramp past the palette, a level over 7, unknown flags, an unknown backdrop, a clock over
MAX_CLOCK, a draw distance cap outside 3..8 (but 0) or a non-zero tail.
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

    def pack(self) -> bytes:
        if not (0 <= self.ground_level <= 7 and self.backdrop < len(BACKDROPS) and self.flags & ~BENCH_ONLY == 0):
            raise ValueError(f"mood {self}: level 0..7, backdrop < {len(BACKDROPS)}, flags {BENCH_ONLY} only")
        if not all(0 <= c <= m for c, m in zip(self.clock, MAX_CLOCK, strict=True)):
            raise ValueError(f"mood clock {self.clock}: start 0..{MAX_CLOCK[0]} s, extension 0..{MAX_CLOCK[1]} s")
        if self.draw_r != 0 and not R_MIN <= self.draw_r <= R_MAX:
            raise ValueError(f"mood draw distance cap {self.draw_r}: 0 (none) or {R_MIN}..{R_MAX} tiles")
        rgbs = (*self.sky, *self.hills)
        if any(not 0 <= c <= 255 for rgb in rgbs for c in rgb):
            raise ValueError(f"mood colours {rgbs}: ints 0..255")
        head = struct.pack("<4B", self.ground_ramp, self.ground_level, self.flags, self.backdrop)
        return head + b"".join(bytes(rgb) + b"\0" for rgb in rgbs) + bytes(self.clock) + bytes([self.draw_r]) + bytes(5)


def unpack(blob: bytes) -> Mood:
    """The mood of a converted track (the defaults when it has no block)."""
    at = struct.unpack_from("<I", blob, 4 * WORD)[0]
    if at == 0:
        return Mood()
    b = blob[at:at + SIZE]
    rgb = [(b[4 + 4 * k], b[5 + 4 * k], b[6 + 4 * k]) for k in range(5)]
    return Mood(b[0], b[1], b[2], b[3], (rgb[0], rgb[1]), (rgb[2], rgb[3], rgb[4]), (b[24], b[25]), b[26])
