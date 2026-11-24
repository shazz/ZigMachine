"""Measure the mating faces of the reference wedge parts (third-party STLs: READ ONLY, never copied).

uv run --with numpy-stl --with numpy python fpga/case/tools/joint_analysis.py <dir> <stl> [<stl>...] [--slice AXIS H]...

With no --slice it prints the bbox and, for each axis, the cross-section loops at 1.5 mm and 4 mm
inside each end of the bbox (loops = holes, bosses, walls seen from that face), plus the extents.
"""
from __future__ import annotations

import sys
from pathlib import Path

import numpy as np
from stl import mesh


def slice_segments(tris: np.ndarray, axis: int, h: float) -> tuple[list, list[int]]:
    o = [i for i in range(3) if i != axis]
    segs = []
    for t in tris:
        d = t[:, axis] - h
        pts = []
        for a, b in ((0, 1), (1, 2), (2, 0)):
            if d[a] * d[b] < 0:
                k = d[a] / (d[a] - d[b])
                pts.append((t[a] + k * (t[b] - t[a]))[o])
        if len(pts) == 2:
            segs.append(pts)
    return segs, o


def loops_of(segs: list) -> list[np.ndarray]:
    adj: dict[tuple, list[tuple]] = {}
    for a, b in segs:
        ka, kb = tuple(np.round(a, 2)), tuple(np.round(b, 2))
        adj.setdefault(ka, []).append(kb)
        adj.setdefault(kb, []).append(ka)
    seen: set = set()
    out = []
    for s in adj:
        if s in seen:
            continue
        stack, comp = [s], []
        while stack:
            p = stack.pop()
            if p in seen:
                continue
            seen.add(p)
            comp.append(p)
            stack += adj[p]
        out.append(np.array(comp))
    return out


def report(tris: np.ndarray, axis: int, h: float) -> None:
    segs, o = slice_segments(tris, axis, h)
    print(f"  slice {'xyz'[axis]}={h:.1f} (axes {'xyz'[o[0]]},{'xyz'[o[1]]}):")
    for lp in sorted(loops_of(segs), key=lambda p: (p[:, 0].min(), p[:, 1].min())):
        lo, hi = lp.min(0), lp.max(0)
        w, c = hi - lo, (lo + hi) / 2
        kind = "round" if len(lp) > 10 and abs(w[0] - w[1]) < 0.3 and max(w) < 25 else "poly "
        print(f"    {kind} n={len(lp):4} centre=({c[0]:.2f},{c[1]:.2f}) size=({w[0]:.2f} x {w[1]:.2f})")


def main() -> None:
    args = sys.argv[1:]
    d = Path(args.pop(0))
    slices = []
    while "--slice" in args:
        i = args.index("--slice")
        slices.append((int(args[i + 1]), float(args[i + 2])))
        del args[i : i + 3]
    for name in args:
        tris = mesh.Mesh.from_file(str(d / name)).vectors
        v = tris.reshape(-1, 3)
        lo, hi = v.min(0), v.max(0)
        print(f"{name}: min {np.round(lo, 2)} max {np.round(hi, 2)} size {np.round(hi - lo, 2)}")
        for axis, h in slices:
            report(tris, axis, h)


if __name__ == "__main__":
    main()
