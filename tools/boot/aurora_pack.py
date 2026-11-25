"""Stage 3 of the baker: aurora frames -> palette indices -> deltas, and the ZX0 containers the cart embeds.

Chosen format (measured in docs/boot/AURORA_BOOT.md): every other row of the lit band, temporal hysteresis
(a pixel keeps its previous entry while the new one is within HYST levels: the error is bounded, nothing
accumulates), then the index difference vs the previous frame mod 256, one ZX0 container per frame.
"""
import subprocess
from pathlib import Path

import numpy as np

import aurora_palette as pal_mod

HYST = 2  # levels (a 565 channel step); the bound on how far a shown pixel may sit from the exact one
ROW_STEP = 2


class PackError(RuntimeError):
    pass


def band_rows(keys):
    """(r0, r1): the rows that ever light up, r0 rounded down to a multiple of ROW_STEP."""
    rows = np.nonzero(keys.any(0).any(1))[0]
    if len(rows) == 0:
        raise PackError("no aurora pixels in any frame")
    return int(rows.min()) // ROW_STEP * ROW_STEP, int(rows.max()) + 1


def stored_rows(arr, r0, r1):
    """The band's even rows (the rows the cart stores and doubles): (n, rows, W)."""
    return arr[:, r0:r1:ROW_STEP]


def headroom(base, r0, r1):
    """Per stored pixel and channel: the most the aurora may add to BOTH rows it covers without overflowing."""
    mx = np.array([31, 63, 31])
    top = mx - base[r0:r1:ROW_STEP]
    bot = np.full_like(top, 99)
    n = base[r0 + 1:r1:ROW_STEP].shape[0]
    bot[:n] = mx - base[r0 + 1:r1:ROW_STEP]
    return np.minimum(top, bot)


def fit_headroom(idx, pal, room):
    """Replace every entry that would overflow base + entry by the nearest one that does not (0 always fits)."""
    bad = (pal[idx] > room[None]).any(-1)
    for t, y, x in zip(*np.nonzero(bad)):
        ok = (pal <= room[y, x]).all(1)
        target = pal[idx[t, y, x]]
        d = (((pal - target) * pal_mod.SCALE) ** 2).sum(1)
        d[~ok] = 1e18
        idx[t, y, x] = int(d.argmin())
    return int(bad.sum())


def hysteresis(idx, pal, eps=HYST):
    """Temporal hold; the final frame is exact (the aurora's end must restore the sky, not sit 2 levels off)."""
    out = idx.copy()
    for t in range(1, len(idx)):
        keep = np.abs(pal[out[t - 1]] - pal[idx[t]]).max(-1) <= eps
        out[t] = np.where(keep, out[t - 1], idx[t])
    out[-1] = idx[-1]
    return out


def deltas(idx):
    d = idx.copy()
    d[1:] = idx[1:] - idx[:-1]
    return d


def undelta(d):
    return np.cumsum(d.astype(np.uint8), axis=0, dtype=np.uint8)


def zx0(data, zx0pack, workdir, name="tmp.bin"):
    """The ZX0 container (zx0pack, verified bit-exact by the tool) of `data`."""
    if not Path(zx0pack).exists():
        raise PackError(f"zx0pack not found at {zx0pack}: build it, see tools/boot/README in docs/boot/AURORA_BOOT.md")
    src, dst = Path(workdir) / name, Path(workdir) / (name + ".zx0")
    src.write_bytes(bytes(data))
    r = subprocess.run([str(zx0pack), str(src), str(dst)], capture_output=True, text=True, check=False)
    if r.returncode != 0:
        raise PackError(f"zx0pack failed: {r.stderr.strip()}")
    return dst.read_bytes()


def pack_frames(d, zx0pack, workdir):
    """(blob, offsets): the per-frame containers back to back and a u32 offset table (n + 1 entries)."""
    parts = [zx0(d[i].tobytes(), zx0pack, workdir) for i in range(len(d))]
    offs = np.cumsum([0] + [len(p) for p in parts]).astype("<u4")
    return b"".join(parts), offs.tobytes()


def pixel_palette(pal):
    """Palette entries as 565 pixel-layout words (r << 11 | g << 5 | b), 256 u16 (padded with 0)."""
    w = np.zeros(256, dtype="<u2")
    p = pal.astype(np.int64)
    w[:len(pal)] = (p[:, 0] << 11) | (p[:, 1] << 5) | p[:, 2]
    return w
