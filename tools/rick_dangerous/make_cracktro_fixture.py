#!/usr/bin/env python3
"""apps/rick_cracktro_fixture.json.gz: the Empire cracktro's screens as the ORIGINAL shows them.

    python3 tools/rick_dangerous/make_cracktro_fixture.py [prototypes/emp_cabl_re/ref]

The input is four raw ST screens (32000 bytes each) that Hatari (TOS 1.62, via
ShirazMCP) showed while EMP_CABL.PRG ran from C:\\AUTO, each frozen by a
breakpoint in the typewriter with a5 at a known text position:
    p04a.bin  $32EBA (the typewriter's entry), a5 = text + $04A, VBL 2291
    p0df.bin  $32EF4 (in $F7, before its wait),  a5 = text + $0E0, VBL 2585
    p2dc.bin  $32EF4, the second $F7,            a5 = text + $2DD, VBL 3614
    p34e.bin  $32F4A (in $FF, before ESC E),     a5 = text + $34F, VBL 3835
(the program copies itself to $30000: TEXT offset t runs at $30000 + t - $32).
`pos` is the text position of the byte the next step reads, before the $F7 /
$FF, so every screen is "after the step that read pos - 1"; the VBLs are one
Hatari run, so their differences are the original's typing time.

Each screen is stored as its ink (colour index != 0), one bit a pixel, MSB
left: the cracktro draws in colours 0 and 15 only (checked here).
"""
from __future__ import annotations

import base64
import gzip
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent.parent
REFS = [("p04a", 0x04A, 2291), ("p0df", 0x0DF, 2585), ("p2dc", 0x2DC, 3614), ("p34e", 0x34E, 3835)]


def ink_bits(screen: bytes) -> bytes:
    """Low-res planar screen -> 1 bit a pixel (colour != 0), rows of 40 bytes."""
    if len(screen) != 32000:
        raise ValueError(f"a screen is 32000 bytes, not {len(screen)}")
    out = bytearray(8000)
    for y in range(200):
        for x in range(320):
            g = y * 160 + (x >> 4) * 8
            b = 15 - (x & 15)
            c = 0
            for p in range(4):
                c |= ((((screen[g + 2 * p] << 8) | screen[g + 2 * p + 1]) >> b) & 1) << p
            if c not in (0, 15):
                raise ValueError(f"colour {c} at ({x},{y}): the cracktro uses 0 and 15 only")
            if c:
                out[y * 40 + (x >> 3)] |= 0x80 >> (x & 7)
    return bytes(out)


def main() -> None:
    src = Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / "prototypes/emp_cabl_re/ref"
    refs = []
    for name, pos, vbl in REFS:
        ink = ink_bits((src / f"{name}.bin").read_bytes())
        refs.append({"name": name, "pos": pos, "vbl": vbl, "ink": base64.b64encode(ink).decode()})
    out = REPO / "apps/rick_cracktro_fixture.json.gz"
    out.write_bytes(gzip.compress(json.dumps({"refs": refs}).encode(), mtime=0))
    print(f"{out}: {len(refs)} screens")


if __name__ == "__main__":
    main()
