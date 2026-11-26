"""The aurora as the cart plays it: no palette. The final picture (sky + aurora in float, the lab's compositing)
rounded to RGB565 once, stored as the 16-bit per-pixel difference from the previous frame (wrapping), in TWO
containers a frame (change mask + nibble codes, aurora_mask.py; offsets 2n + 1); the cart adds it to the plane.
Nothing is dithered: this is the floor of any undithered 565 display of the lab (each channel within half a level).
(The shared and per-row palettes this replaced are in docs/boot/AURORA_BOOT.md, "History".)
"""
import numpy as np

import aurora_mask as mk
import aurora_pack as pk


def lit_rows(mask):
    """(r0, r1): the rows of `mask` (n, H, W) that are ever true."""
    rows = np.nonzero(mask.any(0).any(1))[0]
    if len(rows) == 0:
        raise pk.PackError("no aurora pixels in any frame")
    return int(rows.min()), int(rows.max()) + 1


def words(levels):
    """565 levels (..., 3) -> pixel words r << 11 | g << 5 | b, u16."""
    p = levels.astype(np.uint32)
    return ((p[..., 0] << 11) | (p[..., 1] << 5) | p[..., 2]).astype(np.uint16)


def direct_frames(light, base_f):
    """(n, H, W, 3) int levels: the final picture of every frame, rounded once (clamped to the channel range)."""
    mx = np.array([31, 63, 31], np.float32)
    return np.clip(np.floor(base_f[None] + light + np.float32(.5)), 0, mx).astype(np.int16)


def direct_deltas(final_w, base_w):
    """u16 (n, rows, W): frame t minus frame t-1 (frame -1 = the sky), wrapping."""
    d = final_w.astype(np.uint16).copy()
    d[0] = final_w[0] - base_w
    d[1:] = final_w[1:] - final_w[:-1]
    return d


def probe_frames(n):
    return sorted({0, n // 4, n // 2, 3 * n // 4, n - 1})


def build_direct(light, base_f, base_q):
    """The final 565 picture per frame, 16-bit wrapping deltas, every row of the band, as change masks +
    nibble codes (aurora_mask.py: no ZX0, the board's cost is per changed pixel), two containers a frame."""
    final = direct_frames(light, base_f)
    sky = words(base_q)
    fw = words(final)
    r0, r1 = lit_rows(fw != sky[None])
    d = direct_deltas(fw[:, r0:r1], sky[r0:r1])
    table = mk.delta_table(d, d != 0)
    blob, offs, splits = mk.encode(d, table)
    if (fw[-1] != sky).any():
        raise pk.PackError("the last frame is not the sky: the aurora must end on the clean picture")
    check_round_trip(blob, offs, table, sky[r0:r1], fw[:, r0:r1])
    e = np.abs(final - (base_f[None] + light)).reshape(-1, 3)
    return dict(n=len(fw), r0=r0, rows=r1 - r0, blob=blob, offs=offs, planes={j: fw[j] for j in probe_frames(len(fw))},
                sky=sky, deltas=table, stats=dict(err_mean=e.mean(0).round(3).tolist(), err_max=e.max(0).round(2).tolist(),
                                                           split_rows=[min(splits), max(splits)]))


def check_round_trip(blob, offs, table, sky_band, frames_band):
    """Every frame decodes (the cart's loop, in Python) to the exact picture: the probes pin only 5 of them."""
    o = np.frombuffer(offs, "<u4")
    plane = sky_band.copy()
    for t in range(len(frames_band)):
        for k in (2 * t, 2 * t + 1):
            mk.apply(plane, blob[o[k]:o[k + 1]], table, len(sky_band))
        if not np.array_equal(plane, frames_band[t]):
            raise pk.PackError(f"aurora frame {t} does not decode to its picture")
