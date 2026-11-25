"""The shared aurora palette: 256 RGB565-level DIFFERENCES chosen from every frame's real colours.

No dithering anywhere: each pixel takes its nearest entry. Entry 0 is exactly (0, 0, 0) (no aurora), the
others come from a weighted median cut refined by a fixed number of Lloyd steps (deterministic: no random
init), then sorted by brightness so that index distance follows colour distance (small deltas between
frames pack better). `weight_pow` < 1 favours the rare dark / low-intensity colours of the soft fade.
"""
import numpy as np

SCALE = np.array([8.0, 4.0, 8.0])  # a 565 level in 8-bit-ish units (r5 = 8, g6 = 4, b5 = 8)
LLOYD_STEPS = 12


class PaletteError(ValueError):
    pass


def unpack(keys):
    k = keys.astype(np.int64)
    return np.stack([k & 31, (k >> 5) & 63, (k >> 11) & 31], axis=-1)


def histogram(frames_keys):
    """(unique keys, counts) over all frames."""
    return np.unique(frames_keys, return_counts=True)


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


def _nearest(pts, centres):
    d = ((pts[:, None, :] - centres[None, :, :]) * SCALE) ** 2
    return d.sum(-1).argmin(1)


def build(keys, counts, size=256, weight_pow=0.5):
    """(palette (size, 3) int levels, index_of_key: dict-like array over uniq keys)."""
    if size < 2 or size > 256:
        raise PaletteError(f"palette size {size} outside 2..256")
    pts = unpack(keys).astype(float)
    w = counts.astype(float) ** weight_pow
    nz = np.nonzero(keys != 0)[0]
    if len(nz) == 0:
        raise PaletteError("no aurora pixels in any frame")
    cen = _median_cut(pts[nz], w[nz], size - 1)
    for _ in range(LLOYD_STEPS):
        a = _nearest(pts[nz], cen)
        for c in range(len(cen)):
            m = a == c
            if m.any():
                cen[c] = np.average(pts[nz][m], axis=0, weights=w[nz][m])
    cen = np.unique(np.rint(cen).astype(int), axis=0)
    cen = cen[np.lexsort((cen[:, 2], cen[:, 0], (cen * SCALE).sum(1)))]
    pal = np.vstack([[0, 0, 0], cen[(cen != 0).any(1)]])
    return pal.astype(np.int16)


def quantise(keys_frames, uniq, pal):
    """Index frames (n, H, W) uint8: each pixel's nearest palette entry; 0 stays exactly 0."""
    idx_u = _nearest(unpack(uniq).astype(float), pal.astype(float))
    idx_u[uniq == 0] = 0
    return idx_u.astype(np.uint8)[np.searchsorted(uniq, keys_frames)]


def error(uniq, counts, pal, idx_u):
    """(mean, max) absolute error in 565 levels per channel, pixel-weighted."""
    e = np.abs(unpack(uniq) - pal[idx_u]).astype(float)
    return (e * counts[:, None]).sum(0) / counts.sum(), e.max(0)
