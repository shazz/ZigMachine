"""The shared aurora palette: 256 RGB565-level DIFFERENCES chosen from every frame's real colours.

No dithering anywhere: each pixel takes its nearest entry, and that choice is made on the aurora's FLOAT
light (not on its integer-rounded 565 difference, whose per-channel rounding jitter would flip pixels between
neighbouring entries and read as speckle): the cell boundaries are then smooth contours. Entry 0 is exactly
(0, 0, 0) (no aurora); the others come from a weighted median cut refined by a fixed number of Lloyd steps
(deterministic: no random init), snapped to integer levels (they are added to a 565 pixel), sorted by
brightness so that index distance follows colour distance. `weight_pow` < 1 favours the rare dark /
low-intensity colours of the soft fade.
"""
import numpy as np

SCALE = np.array([8.0, 4.0, 8.0])  # a 565 level in 8-bit-ish units (r5 = 8, g6 = 4, b5 = 8)
LLOYD_STEPS = 12
LATTICE = 4  # histogram cell: 1/4 of a level
CHUNK = 200_000


class PaletteError(ValueError):
    pass


def histogram(frames_f):
    """(points, counts): the distinct 1/4-level cells of every frame's float deltas (n, H, W, 3), as float levels."""
    q = np.rint(frames_f * LATTICE).astype(np.int64)
    key = q[..., 0] | (q[..., 1] << 10) | (q[..., 2] << 20)
    uniq, counts = np.unique(key, return_counts=True)
    pts = np.stack([uniq & 1023, (uniq >> 10) & 1023, (uniq >> 20) & 1023], -1) / LATTICE
    return pts, counts


def _median_cut(pts, w, n):
    boxes = [np.arange(len(pts))]
    while len(boxes) < n:
        i = max(range(len(boxes)), key=lambda j: (np.ptp(pts[boxes[j]] * SCALE, axis=0).max() * w[boxes[j]].sum()
                                                   if len(boxes[j]) > 1 else -1))
        idx = boxes.pop(i)
        if len(idx) < 2:
            boxes.append(idx)
            break
        axis = int(np.argmax(np.ptp(pts[idx] * SCALE, axis=0)))
        order = idx[np.argsort(pts[idx, axis], kind="stable")]
        cum = np.cumsum(w[order])
        cut = int(np.clip(np.searchsorted(cum, cum[-1] / 2), 1, len(order) - 1))
        boxes += [order[:cut], order[cut:]]
    return np.array([np.average(pts[b], axis=0, weights=w[b]) for b in boxes])


def nearest(pts, centres):
    """Index of the nearest centre for each point (N, 3), in perceptual units, chunked matrix maths."""
    a, c = pts * SCALE, centres * SCALE
    c2 = (c * c).sum(1)
    out = np.empty(len(a), dtype=np.int64)
    for i in range(0, len(a), CHUNK):
        blk = a[i:i + CHUNK]
        out[i:i + CHUNK] = ((blk * blk).sum(1)[:, None] - 2 * blk @ c.T + c2[None]).argmin(1)
    return out


def build(pts, counts, size=256, weight_pow=0.5):
    """The palette (<= size, 3) of int levels from histogram points."""
    if size < 2 or size > 256:
        raise PaletteError(f"palette size {size} outside 2..256")
    live = np.nonzero((pts >= 0.5).any(1))[0]  # cells that round to some light
    if len(live) == 0:
        raise PaletteError("no aurora pixels in any frame")
    p, w = pts[live], counts[live].astype(float) ** weight_pow
    cen = _median_cut(p, w, size - 1)
    for _ in range(LLOYD_STEPS):
        a = nearest(p, cen)
        tot = np.bincount(a, weights=w, minlength=len(cen))
        for ch in range(3):
            sums = np.bincount(a, weights=w * p[:, ch], minlength=len(cen))
            cen[:, ch] = np.where(tot > 0, sums / np.maximum(tot, 1e-12), cen[:, ch])
    cen = np.unique(np.rint(cen).astype(int), axis=0)
    cen = cen[(cen != 0).any(1)]
    cen = cen[np.lexsort((cen[:, 2], cen[:, 0], (cen * SCALE).sum(1)))]
    return np.vstack([[0, 0, 0], cen]).astype(np.int16)


def quantise(frames_f, pal):
    """Index frames (n, H, W) uint8: each pixel's nearest palette entry (on the float light); no dither."""
    flat = frames_f.reshape(-1, 3)
    return nearest(flat, pal.astype(float)).astype(np.uint8).reshape(frames_f.shape[:-1])


def error(frames_f, idx, pal):
    """(mean, max) absolute error in 565 levels per channel against the float light."""
    e = np.abs(frames_f - pal[idx]).reshape(-1, 3)
    return e.mean(0), e.max(0)
