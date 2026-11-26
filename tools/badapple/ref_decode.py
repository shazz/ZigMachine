#!/usr/bin/env python3
"""The reference decoder: ref_decode.py STREAM OUT [i,j,k]  writes frames i,j,k (default all), 64,000 bytes of 0/1 each,
concatenated. ZX0 and the format are decoded by tools/badapple/{zx0,spans}.py, not by the cart's code."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from badapple import spans  # noqa: E402


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    want = {int(n) for n in argv[3].split(",")} if len(argv) > 3 else None
    with open(argv[2], "wb") as out:
        for i, rows in enumerate(spans.iter_rows(Path(argv[1]).read_bytes())):
            if want is None or i in want:
                out.write(spans.paint(rows))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
