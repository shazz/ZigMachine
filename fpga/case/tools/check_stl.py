"""Check the exported parts: bounding box vs the print bed and watertightness (every edge shared by 2 faces).

uv run --with numpy-stl --with numpy python fpga/case/tools/check_stl.py [bed_x bed_y]
"""
from __future__ import annotations

import sys
from collections import Counter
from pathlib import Path

import numpy as np
from stl import mesh

STL = Path(__file__).resolve().parent.parent / "stl"


def edge_counts(tris: np.ndarray) -> Counter:
    key = lambda p: tuple(np.round(p, 4))  # noqa: E731 [lambda is the shortest way to a vertex key]
    c: Counter = Counter()
    for t in tris:
        for a, b in ((0, 1), (1, 2), (2, 0)):
            c[frozenset((key(t[a]), key(t[b])))] += 1
    return c


def main() -> int:
    bed = (float(sys.argv[1]), float(sys.argv[2])) if len(sys.argv) > 2 else (190.0, 180.0)
    bad = 0
    for f in sorted(STL.glob("*.stl")):
        tris = mesh.Mesh.from_file(str(f)).vectors
        v = tris.reshape(-1, 3)
        size = v.max(0) - v.min(0)
        open_edges = sum(1 for n in edge_counts(tris).values() if n != 2)
        fits = size[0] <= bed[0] and size[1] <= bed[1]
        print(f"{f.name}: {size[0]:.1f} x {size[1]:.1f} x {size[2]:.1f} mm, bed {'OK' if fits else 'TOO BIG'}, "
              f"{len(tris)} faces, non-manifold edges: {open_edges}")
        bad += (not fits) + (open_edges > 0)
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
