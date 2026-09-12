#!/usr/bin/env python3
"""Extract the D-BUG credit-panel apparition patterns from the original Codef source.

The screen (wab.com/screen.php?screen=556, Shiftcode/CODEF) reveals its 20x12
credit panel one cell per frame, in an order taken from `patterns` in data.js --
seven hand-authored permutations of the 240 cell indices (up_down, down_zigzag,
left_right, inward_spiral, down_up, up_zigzag, right_left).

They are pure data, so they are shipped as a flat .dat rather than 1680 numbers
of Zig source: 7 tables x 240 cells, one u8 per cell (every index is < 240).

    tools/dbug_patterns.py            # regenerate patterns.dat in place
    tools/dbug_patterns.py --check    # verify the committed .dat still matches
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ASSETS = Path(__file__).resolve().parent.parent / "apps/zig/assets/screens/dbug"
DATA_JS = ASSETS / "data.js"
OUT = ASSETS / "patterns.dat"

CELLS = 20 * 12


def parse(js: str) -> list[tuple[str, bytes]]:
    """Return [(effect name, 240 cell indices)] in the order `patterns` lists them."""
    effects: dict[str, bytes] = {}
    for name, body in re.findall(r"effects\['(\w+)'\]\s*=\s*\[(.*?)\]", js, re.S):
        cells = [int(n) for n in re.findall(r"\d+", body)]
        if sorted(cells) != list(range(CELLS)):
            raise ValueError(f"effect '{name}' is not a permutation of 0..{CELLS - 1}")
        effects[name] = bytes(cells)

    # `];` and not `]`: the body itself contains `effects['name']` brackets.
    order = re.search(r"const patterns\s*=\s*\[(.*?)\];", js, re.S)
    if not order:
        raise ValueError("no `const patterns = [...]` table in data.js")
    names = re.findall(r"effects\['(\w+)'\]", order.group(1))
    if not names:
        raise ValueError("`patterns` lists no effects")
    return [(n, effects[n]) for n in names]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--check", action="store_true", help="verify instead of writing")
    ap.add_argument("--data", type=Path, default=DATA_JS, help="path to the original data.js")
    args = ap.parse_args()

    tables = parse(args.data.read_text(encoding="utf-8", errors="replace"))
    blob = b"".join(cells for _, cells in tables)

    if args.check:
        current = OUT.read_bytes() if OUT.exists() else b""
        if current != blob:
            print(f"MISMATCH: {OUT} is stale (regenerate with tools/dbug_patterns.py)")
            return 1
        print(f"OK: {OUT} matches {args.data} ({len(tables)} patterns)")
        return 0

    OUT.write_bytes(blob)
    print(f"wrote {OUT} -- {len(tables)} patterns x {CELLS} cells = {len(blob)} bytes")
    for i, (name, _) in enumerate(tables):
        print(f"  [{i}] {name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
