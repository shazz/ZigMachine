#!/usr/bin/env python3
"""Extract the D-BUG screen's music-synced motion curves from the Codef original.

`screen.js` does not animate the scroller or the logo with a sine — it drives
them from the tune's playback position (sndhMonitor): the scroller FALLS at
12800 ms, then bounces once per beat, and every bounce re-triggers the logo's
spring. The shapes of those three moves are hand-authored tables in data.js.

Coordinate spaces differ, so the values are converted here rather than at
runtime:

  scroller y   the original canvas is 768x540 with a 384-tall scroller, so its
               y runs 0..148 (rest 74). Ours is the 400x280 overscan page with a
               192-tall scroller, y running 0..88. Scaled by 88/148.
  logo y       ysine is an ABSOLUTE y that decays back to its rest of 16. We
               keep it as a signed DELTA from rest, halved for our screen, so
               the scene can apply it to wherever its logo sits.

Output: apps/zig/assets/screens/dbug/curves.dat
  [0]  u16 count of each of the four tables (bounce_start, bounce, bounce_stop, spring)
  then bounce_start / bounce / bounce_stop as u8 y values,
  then spring as i8 deltas.

    tools/dbug_curves.py            # regenerate
    tools/dbug_curves.py --check    # verify the committed .dat still matches
"""

from __future__ import annotations

import argparse
import re
import struct
import sys
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / "apps/zig/assets/screens/dbug"
DATA_JS = ASSETS / "data.js"
OUT = ASSETS / "curves.dat"

# The original's scroller travel and ours (see the module docstring).
ORIGINAL_TRAVEL = 148
OUR_TRAVEL = 88
SPRING_REST = 16


def hexa_to_curve(text: str) -> list[int]:
    """data.js hexaToCurve: byte pairs, then .map(x => x + x) — i.e. doubled."""
    return [int(text[i : i + 2], 16) * 2 for i in range(0, len(text), 2)]


def scroller_y(v: int) -> int:
    return round(v * OUR_TRAVEL / ORIGINAL_TRAVEL)


def grab(js: str, name: str) -> str:
    m = re.search(rf"const {name}\s*=\s*hexaToCurve\('([0-9A-Fa-f]+)'\)", js)
    if not m:
        raise ValueError(f"no hexaToCurve table named {name} in data.js")
    return m.group(1)


def parse(js: str) -> tuple[list[int], list[int], list[int], list[int]]:
    curves = [[scroller_y(v) for v in hexa_to_curve(grab(js, n))]
              for n in ("bounceStart", "bounce", "bounceStop")]

    m = re.search(r"const ysine\s*=\s*'([0-9a-fA-F]+)'", js)
    if not m:
        raise ValueError("no ysine table in data.js")
    # ysine: one hex DIGIT per frame, doubled — an absolute y that settles at 16.
    spring = [(int(c, 16) * 2 - SPRING_REST) // 2 for c in m.group(1)]
    return curves[0], curves[1], curves[2], spring


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="verify instead of writing")
    ap.add_argument("--data", type=Path, default=DATA_JS)
    args = ap.parse_args()

    start, bounce, stop, spring = parse(args.data.read_text(encoding="utf-8", errors="replace"))
    for name, c in (("bounceStart", start), ("bounce", bounce), ("bounceStop", stop)):
        if not all(0 <= v <= 255 for v in c):
            raise ValueError(f"{name} left the byte range after scaling")
    if not all(-128 <= v <= 127 for v in spring):
        raise ValueError("spring deltas left the signed-byte range")

    blob = struct.pack("<4H", len(start), len(bounce), len(stop), len(spring))
    blob += bytes(start) + bytes(bounce) + bytes(stop)
    blob += struct.pack(f"<{len(spring)}b", *spring)

    if args.check:
        if (OUT.read_bytes() if OUT.exists() else b"") != blob:
            print(f"MISMATCH: {OUT} is stale (regenerate with tools/dbug_curves.py)")
            return 1
        print(f"OK: {OUT} matches {args.data}")
        return 0

    OUT.write_bytes(blob)
    print(f"wrote {OUT} — {len(blob)} bytes")
    print(f"  fall    {len(start):3} frames, y {min(start)}..{max(start)}")
    print(f"  bounce  {len(bounce):3} frames, y {min(bounce)}..{max(bounce)}")
    print(f"  settle  {len(stop):3} frames, y {min(stop)}..{max(stop)}")
    print(f"  spring  {len(spring):3} frames, delta {min(spring)}..{max(spring)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
